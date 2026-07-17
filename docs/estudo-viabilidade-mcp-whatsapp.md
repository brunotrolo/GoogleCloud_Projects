# Estudo de viabilidade — MCP pessoal de alertas via WhatsApp

**Data da pesquisa:** 2026-07-16 · **Escopo:** só receber alertas (mão única, você mesmo destinatário, <10 msgs/dia) · **Não é implementação** — nenhum servidor foi criado, nenhuma conta foi aberta, nenhum custo real foi gerado.

**Decisão já tomada (fora deste estudo):** projeto GCP novo + repositório novo, isolados dos MCPs OpLab/Cockpit — mantida no desenho abaixo.

---

## 🔴 Veredito logo no topo (como pedido — sem enrolar)

**1. Cloud Run não sustenta a sessão do WhatsApp via Evolution API/Baileys. Não é uma questão de configuração — é incompatibilidade estrutural.**
Uma conexão WhatsApp Web (Baileys) é um WebSocket de longa duração. No Cloud Run: (a) qualquer instância com WebSocket aberto **não escala a zero** — fica ativa e cobrando, matando o `min-instances=0` que sustenta nosso custo ~R$0 hoje; (b) o Cloud Run **força timeout de 60 minutos** em toda conexão WebSocket, então a sessão cairia a cada hora mesmo pagando por instância sempre ligada.¹ **Precisa de Compute Engine (VM sempre ligada) ou GKE — não dá para reaproveitar o padrão Cloud Run que usamos no OpLab/Cockpit.**

**2. A premissa "baixo volume reduz o risco de banimento" está desmentida pela pesquisa.**
O prompt original pediu para eu levantar a taxa de bloqueio "para uso de baixo volume... bem diferente de disparo em massa". A pesquisa mostra o oposto: **~1 em cada 5 contas usando API não-oficial (Baileys e afins) é banida em até 1 ano**, e o fator de risco é *irrelevância/padrão heurístico*, não volume — uma conta mandando 100 msgs/dia com baixo engajamento é **mais** arriscada que uma mandando 10.000/dia com alto engajamento.² Para o seu caso (mensagens automáticas, sem resposta, sempre para o mesmo número), o padrão é exatamente o perfil que a detecção por ML mira. **Baixo volume não te protege.**

**3. Existe uma 4ª opção que o estudo original não considerou, e ela provavelmente resolve o problema todo: a API oficial da Meta (WhatsApp Cloud API) direta, sem BSP.**
Desde julho/2025 o Brasil fatura por **mensagem** (não mais por conversa de 24h), e mensagens de categoria **Utility** (o seu caso — alerta transacional, não marketing) custam **~R$0,04–0,05 cada**.³ Para <10 msgs/dia (≤300/mês) isso é **~R$12–15/mês**, com **risco de banimento ≈ zero** (é o canal oficial) e infraestrutura **stateless** — encaixa perfeitamente no padrão Cloud Run `min-instances=0` que já usamos, sem VM, sem Postgres, sem Redis. Ainda mais: em modo *sandbox/desenvolvimento*, a Meta permite mandar mensagens grátis para até 5 números de teste **sem verificação de empresa**, o que pode cobrir seu caso (você mandando pra você mesmo) indefinidamente, a custo zero.⁴

**Recomendação prévia ao restante do relatório:** dado (1) e (2), a rota Evolution API self-hosted deixa de ser "simples" (vira VM + Postgres, e talvez Redis) e continua com risco real de perda do número. A rota (3) é mais barata, mais simples de manter e sem risco — mas é um caminho diferente do que o prompt original pediu para investigar. Abaixo está o estudo completo dos 3 cenários pedidos, **mais** o 4º como contraponto, para você decidir com os números todos na mesa.

---

## 1. Viabilidade técnica da Evolution API no GCP

| Requisito | Evolution API precisa de | Cloud Run serve? | Alternativa GCP |
|---|---|---|---|
| Sessão WhatsApp (Baileys, WebSocket 24/7) | Conexão persistente, nunca cair | ❌ Não (WebSocket pinned à instância + timeout 60min + impede scale-to-zero)¹ | **Compute Engine** (VM sempre ligada) ou GKE |
| Banco de dados (instâncias, mensagens, contatos) | PostgreSQL | Indiferente (roda em qualquer host) | Cloud SQL **ou** Postgres em container na própria VM |
| Cache/fila de sessão | Redis — **mas existe modo "lightweight" sem Redis**, usando cache local, recomendado para uso de baixo volume⁵ | Indiferente | Memorystore (caro, ver §2) **ou pular Redis** (recomendado aqui) |
| Volume persistente | Disco para a credencial de sessão do WhatsApp (`auth_info`) sobreviver a restart | ❌ (Cloud Run é stateless/efêmero por design) | Persistent Disk anexado à VM |

**Conclusão técnica:** o único caminho viável no GCP é **Compute Engine com 1 VM sempre ligada**, rodando Evolution API + Postgres (+ opcionalmente Redis) via Docker Compose, com um Persistent Disk para a sessão. GKE seria overkill para 1 instância de baixíssimo volume — descartado por complexidade desnecessária.

---

## 2. Estimativa de custo mensal no GCP (Compute Engine)

Fontes: [Cloud SQL pricing](https://cloud.google.com/sql/pricing), [economize.cloud e2-small](https://www.economize.cloud/resources/gcp/pricing/compute-engine/e2-small/), [economize.cloud f1-micro](https://www.economize.cloud/resources/gcp/pricing/compute-engine/f1-micro/), [Memorystore Redis pricing](https://cloud.google.com/memorystore/docs/redis/pricing), [Disk pricing](https://cloud.google.com/compute/disks-image-pricing), [GCP Always Free](https://cloud.google.com/free) — consultadas em 2026-07-16. Câmbio de referência: US$1 ≈ R$5,50.

| Item | Opção enxuta | Opção com folga | Observação |
|---|---|---|---|
| Compute (VM) | e2-micro — **US$0/mês** (Always Free, 1 por conta, elegível em us-east1/us-west1/us-central1)⁶ | e2-small (2 vCPU, 2GB) — **US$12,23/mês**⁷ | e2-micro (1 vCPU burstable, 1GB RAM) é o mínimo testado pela doc da Evolution API⁸, mas sem folga para Node+Postgres+Baileys juntos sob carga real — risco de throttling |
| PostgreSQL | Container na própria VM — **US$0** incremental | Cloud SQL `db-f1-micro` — **US$7–10/mês**⁹ | Self-managed no container é viável para 1 usuário, mas você perde backup automático e HA do Cloud SQL |
| Redis | **Pular** (modo lightweight, cache local)⁵ — **US$0** | Memorystore 1GB (M1) — **US$36/mês**¹⁰ | Redis é o item mais caro de todos — **maior que VM+banco somados**. Só se justifica em produção de alto volume; para <10 msgs/dia, pular é a decisão correta |
| Disco persistente | 20GB Standard — **US$0,80/mês** (US$0,04/GB)¹¹ | 20GB — igual | Free tier inclui 30GB de disco Standard em US regions, então pode cair a **US$0** combinado com o e2-micro |
| **TOTAL — cenário enxuto** | **US$0 a ~US$1/mês** (≈ **R$0–5,50/mês**) | | Usa 100% do Always Free tier (VM + disco); risco: fragilidade sob carga e concorrência de quota com outros usos do free tier na conta |
| **TOTAL — cenário realista/estável** | **US$12,23 (VM) + US$8 (Cloud SQL) + US$0,80 (disco) ≈ US$21/mês** (≈ **R$115/mês**) | | Sem Redis. Com Redis: **+US$36 → ≈ US$57/mês (≈ R$310/mês)** — evitar |

### Comparação lado a lado (pedida no prompt)

| Opção | Custo mensal (R$) |
|---|---|
| Evolution API — GCP, cenário enxuto (free tier) | **R$0–5** |
| Evolution API — GCP, cenário realista (sem Redis) | **R$115** |
| Evolution API — GCP, com Redis (não recomendado) | **R$310** |
| Evolution API — VPS terceiro (Railway/Easypanel, já levantado) | R$20–50 |
| Z-API (gerenciado) | R$55–99 |
| **WhatsApp Cloud API oficial (não pedida, mas relevante — ver §0)** | **R$0 (sandbox) a R$15 (produção)** |

**Leitura dos números:** o cenário "enxuto" no GCP parece competir com a VPS de terceiro, mas depende 100% do Always Free tier — que é por **conta**, não por projeto, e pode já estar parcialmente consumido pelos MCPs existentes (verificar antes de contar com ele). O cenário realista (R$115/mês) é **mais caro que Z-API** e ainda carrega o risco de banimento do item 3 abaixo — ou seja, self-hosted no GCP só compensa financeiramente no cenário frágil (free tier).

---

## 3. Complexidade de manutenção (o custo invisível)

| Frente | O que exige de você |
|---|---|
| Atualizações da Evolution API | Releases frequentes (semanas), principalmente para acompanhar mudanças no protocolo do WhatsApp que o Baileys precisa contornar. Sem atualizar, o risco de quebra/detecção sobe. |
| Baileys (engenharia reversa do protocolo) | Depende inteiramente da comunidade open-source acompanhar mudanças que a Meta faz para *dificultar* justamente esse tipo de cliente não-oficial — é uma corrida armamentista permanente.² |
| Sessão caindo (logout remoto, troca de aparelho, detecção) | Sim, precisa escanear o QR code de novo manualmente. **Os alertas ficam mudos até você perceber e refazer o pareamento** — não há como automatizar esse passo (é uma limitação de segurança do próprio WhatsApp). |
| **Risco de banimento do número** | Ver achado #2 no topo: **~20% ao ano**, independente de volume.² Se for o seu número pessoal, a perda é de identidade/contatos, não só do canal de alerta — risco desproporcional ao benefício de "alertas de delta". |

---

## 4. Desenho do MCP (arquitetura, não implementação)

- **Ferramentas:** provavelmente 1 só — `enviar_mensagem_whatsapp(texto)` — chamando a REST API da Evolution API (`POST /message/sendText/{instance}`) ou, na rota oficial, o endpoint `POST /{phone-number-id}/messages` da Graph API da Meta.
- **Projeto/repo:** conforme já decidido, projeto GCP **novo** e repositório **novo** (ex.: `whatsapp-mcp-server`), isolado dos MCPs OpLab/Cockpit — sem billing/quota compartilhados, sem risco de vazamento de credencial cruzada.
- **Topologia (Evolution API):** o MCP (Cloud Run, `min-instances=0`, igual ao padrão atual) chama, via HTTP interno, a Evolution API rodando na VM Compute Engine do mesmo projeto novo. O MCP em si continua leve e stateless; só a Evolution API precisa da VM.
- **Topologia (Cloud API oficial):** o MCP roda **inteiramente** no padrão Cloud Run atual — chama a Graph API da Meta direto via HTTPS, sem VM nenhuma. É a única das opções que reaproveita 100% da arquitetura existente.
- **Esforço de desenvolvimento (estimativa, não compromisso):**
  - Evolution API self-hosted: **1–2 dias** — provisionar VM, subir Docker Compose (Evolution + Postgres), escanear QR, escrever o MCP wrapper, testar.
  - WhatsApp Cloud API oficial: **meio dia a 1 dia** — criar app no Meta for Developers, configurar WABA (sandbox), pegar token, escrever o MCP wrapper (mais simples, é só um POST HTTPS).
  - Z-API: **1–2 horas** — criar conta, escanear QR, escrever o MCP wrapper contra a REST deles.

---

## 5. Comparação final

| Opção | Custo mensal | Esforço de setup | Esforço de manutenção contínua | Risco de bloqueio/instabilidade |
|---|---|---|---|---|
| Evolution API self-hosted no GCP (cenário realista) | ~R$115/mês | Médio (1–2 dias; requer VM + Docker Compose) | Médio-alto (updates frequentes, QR re-scan manual) | **~20%/ano de banimento**² — mesmo em baixo volume |
| Evolution API self-hosted no GCP (free tier, frágil) | R$0–5/mês | Médio (idem) | Idem + risco de estourar quota free-tier compartilhada | Idem |
| Evolution API em VPS terceiro (Railway/Easypanel) | R$20–50/mês | Médio (idem, fora do GCP) | Médio-alto (idem) | Idem |
| Z-API (gerenciado, pago) | R$55–99/mês | Baixo | Baixo (suporte deles cobre updates) | **Ainda é conexão não-oficial** — a estatística de ~20%/ano provavelmente se aplica também (não é imune por ser pago) |
| **WhatsApp Cloud API oficial (Meta), direta** | **R$0 (sandbox) – R$15/mês (produção)** | **Baixo** (meio dia) | **Baixíssimo** (é a Meta mantendo, não você) | **Mínimo** — canal oficial, não sujeito a detecção |

---

## Recomendação

Para o seu caso específico (só você, só alertas, baixo volume): a **WhatsApp Cloud API oficial** é estruturalmente superior nos 4 critérios — mais barata, mais simples, menos manutenção, sem risco de perder o número. O único motivo para escolher Evolution API seria querer usar o **mesmo número pessoal como remetente** sem registrar um número separado como "bot" — mas isso é exatamente o que gera o risco de banimento. Se topar usar um número secundário (chip pré-pago barato ou eSIM) só como remetente do bot, a rota oficial resolve tudo com o menor custo total (dinheiro + tempo + risco).

Se quiser, no próximo passo eu detalho o setup da Cloud API oficial (sandbox mode primeiro, sem custo) com o mesmo nível de profundidade que usei nos MCPs OpLab/Cockpit.

---

## Fontes (consultadas em 2026-07-16)

1. Cloud Run WebSocket scaling — [Google Cloud Run docs](https://cloud.google.com/run/docs/triggering/websockets), [ahmetb/cloud-run-faq](https://github.com/ahmetb/cloud-run-faq/blob/master/README.md), [SystemsArchitect.io — WebSocket timeout limits](https://www.systemsarchitect.io/services/gcp-run/seek-alternatives-if-you-need/pt/gcp-run-seek-alternatives-if-you-need-websocket-connections-exceeding-timeout-limits)
2. Taxa de banimento e relação com volume/relevância — [Baileys GitHub Issue #1869](https://github.com/WhiskeySockets/Baileys/issues/1869), [Baileys Discussion #2357](https://github.com/WhiskeySockets/Baileys/discussions/2357), [Kraya AI — WhatsApp Automation Ban Risk](https://blog.kraya-ai.com/whatsapp-automation-ban-risk)
3. Faturamento por mensagem no Brasil (Utility ~R$0,04–0,05) — [Message Central — WhatsApp Pricing Brazil 2026](https://www.messagecentral.com/blog/whatsapp-business-api-pricing-brazil), [go4whatsup — Brazil pricing](https://www.go4whatsup.com/brazil/whatsapp-business-api-pricing/)
4. Sandbox/dev mode gratuito até 5 números — [Meta Developers — WhatsApp Pricing](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing)
5. Modo lightweight sem Redis — [Railway — Evolution API com PostgreSQL](https://railway.com/deploy/self-host-evolution-api), [Evolution API Docs — Redis](https://doc.evolution-api.com/v2/en/requirements/redis)
6. GCP Always Free — [cloud.google.com/free](https://cloud.google.com/free), [dev.to — GCP Free Tier Guide](https://dev.to/jeaniscoding/how-to-host-your-side-projects-for-0-the-ultimate-gcp-free-tier-guide-3p07)
7. e2-small pricing — [economize.cloud](https://www.economize.cloud/resources/gcp/pricing/compute-engine/e2-small/)
8. Requisito mínimo de RAM (teste) — [Senate.sh — Self-host Evolution API](https://senate.sh/apps/evolution-api)
9. Cloud SQL db-f1-micro — [Cloud SQL pricing oficial](https://cloud.google.com/sql/pricing), [Usage.ai — Cloud SQL Pricing 2026](https://www.usage.ai/blogs/gcp/cloud-sql/pricing/)
10. Memorystore Redis M1 — [Memorystore for Redis pricing oficial](https://cloud.google.com/memorystore/docs/redis/pricing), [Upstash — Redis Pricing Comparison 2026](https://upstash.com/blog/redis-pricing-comparison-every-major-provider-in-2026-with-numbers)
11. Persistent Disk Standard — [Google Cloud — Disk pricing](https://cloud.google.com/compute/disks-image-pricing)
12. Z-API — [z-api.io](https://z-api.io/), [Zapster Blog — Z-API vs Zapster 2026](https://blog.zapsterapi.com/post/z-api-whatsapp-vs-zapster-precos-e-diferencas-2026)

**Ressalva:** preços de nuvem e de APIs de mensageria mudam com frequência; os números acima são um retrato de 2026-07-16 e devem ser reconferidos antes de qualquer decisão de compra.

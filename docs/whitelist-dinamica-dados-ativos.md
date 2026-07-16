# Whitelist padrão do OpLab = aba DADOS_ATIVOS (fim da deriva)

**Data:** 2026-07-15 · **MCP:** OpLab · **Arquivos:** `patches/oplab_mcp/{whitelist_source.ts, iv_calculator.ts, index.ts, whitelist_source.test.ts}`

## Problema
A whitelist padrão (fallback quando `tickers` não é informado) estava hardcoded em
`iv_calculator.ts` (`WHITELIST_24`, 27 ativos) e **desalinhada** com a aba `DADOS_ATIVOS`
da planilha — a fonte de verdade mantida pelo operador. O topo do ranking de IV Rank vinha
sugerindo "vender agora" em ativos já removidos da carteira (COGN3, CPLE6, CMIN3), e faltavam
ativos já validados (EQTL3, EGIE3, BPAC11).

Consumidores da mesma constante central: `get_iv_rank_bulk`, `get_smart_money_tracker`,
`get_backtest_protocolo2`, `get_backtest_estrutural`, `get_analise_manejo`.

## Correção
1. **Lista fixa atualizada** para os 26 ativos da `DADOS_ATIVOS` (15/07/2026):

   | | Ativos |
   |---|---|
   | Removidos (4) | CMIN3, COGN3, CPLE6, ELET3 |
   | Adicionados (3) | EQTL3, EGIE3, BPAC11 |
   | (CSAN3 permanece — ainda está na planilha) | |

2. **Sincronização dinâmica (fim da deriva):** se a env `DADOS_ATIVOS_CSV_URL` estiver
   configurada (endpoint "Publicar na web → CSV" da aba `DADOS_ATIVOS`), o servidor lê a
   lista de lá com **cache de 4h** e atualiza `WHITELIST_24` **in-place**. Como todos os
   consumidores leem `[...WHITELIST_24]` no momento da chamada e a atualização é feita num
   único ponto do dispatch (`index.ts`), vale para todas as ferramentas sem tocar em cada arquivo.
   Em qualquer falha (env ausente, rede, HTTP, CSV com <5 tickers) → **fallback para a lista
   fixa**, nunca quebra uma chamada.

### Por que CSV e não Google Sheets API?
O servidor OpLab não tem credenciais de planilha (só `OPLAB_ACCESS_TOKEN` + a API OpLab).
Adicionar `googleapis` reintroduziria o cold-start que já custou caro no MCP Cockpit. O CSV
"Publicar na web" é lido por `fetch` puro, sem credencial nem dependência pesada.

## Limitação e resync manual
Enquanto `DADOS_ATIVOS_CSV_URL` **não** estiver setada, a lista é uma **cópia manual** da aba
e precisa ser resincronizada à mão (rodar o deploy) sempre que a planilha mudar. Para eliminar
isso de vez, publique a aba como CSV e ligue a env (instruções no topo de
`scripts/aplicar_whitelist_dinamica.sh`).

## Validação (antes/depois)
`get_iv_rank_bulk` sem `tickers`, em produção (antes):
- 27 ativos; #1 COGN3 e #2 CPLE6 marcados "EXCELENTE — vender agora" (ativos já removidos).

Depois (novo fallback): 26 ativos, sem COGN3/CPLE6/CMIN3/ELET3, com EQTL3/EGIE3/BPAC11.
Testes do núcleo: `node --experimental-strip-types patches/oplab_mcp/whitelist_source.test.ts` (7/7).

## Deploy
`./scripts/aplicar_whitelist_dinamica.sh` — roda os testes antes de subir. Para ligar a
sincronização dinâmica: `DADOS_ATIVOS_CSV_URL="https://..." ./scripts/aplicar_whitelist_dinamica.sh`.

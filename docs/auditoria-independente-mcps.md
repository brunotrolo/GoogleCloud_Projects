# Auditoria independente dos MCPs (recálculo do zero)

**Data:** 2026-07-16 · **Princípio:** cada valor da ferramenta é conferido por um caminho
matematicamente **independente** (fórmula fechada de livro-texto ou fonte de dado alternativa),
nunca reimplementando a lógica interna da própria ferramenta.

**Amostra fixa:** ITUB4, CSAN3, BBDC4, VALE3, EQTL3.

---

## Veredito por ferramenta

| # | Ferramenta | Conferência | Ferramenta | Independente | Veredito |
|---|---|---|---|---|---|
| 1 | OpLab `get_quote` | spot ITUB4 / BBDC4 | 43,14 / 18,60 | `get_stock` BBDC4 = 18,60 (concorda) | ✅ endpoints de cotação consistentes |
| 1 | " | spot na CADEIA de opções | 43,05–43,63 (varia!) | quote = 43,14 | ⚠️ campo `spot_price` da chain é stale/inconsistente — **não usar para pricing** |
| 2 | OpLab `get_options_bs` | ITUBH435, spot 43,14 vs 48,00 | **1,9141 nas DUAS** (ecoa 43,63) | BS-texto: 1,2854 (S=43,14) vs 5,27 (S=48) | 🔴 **BUG: ignora `spotprice`/`vol`/`dtm`** |
| 2 | " | modo BS "puro" (symbol=ITUB4) | **erro 500 (Redis mget)** | — | 🔴 **BUG: modo ação quebrado** |
| 3 | OpLab `get_analise_estrutura` | ITUB4 topos 40,82→41,63 / fundos ↑ | asc=true | valores ascendentes → true | ✅ booleanos corretos |
| 3 | " | BBDC4 topos 17,80→17,93→17,98 | asc=true | ascendentes → true | ✅ |
| 3 | " | VALE3 topos 82,74→81,58→79,32 | asc=false | descendentes → false | ✅ sem inversão |
| 4 | OpLab `get_iv_rank_historico` | ITUB4 | 55,3 | (23,4−11,8)/(32,8−11,8)·100 = 55,24 | ✅ |
| 4 | " | CSAN3 | 29,0 | 20,7/71,2·100 = 29,07 | ✅ |
| 4 | " | BBDC4 | 61,3 | 12,8/20,9·100 = 61,24 | ✅ |
| 4 | " | VALE3 | 61,4 | 19,6/32,0·100 = 61,25 | ✅ |
| 4 | " | EQTL3 | 51,6 | 13,4/26,0·100 = 51,54 | ✅ |
| 5 | OpLab `get_backtest_*` | 3 ops + anti-look-ahead | — | (não re-executado nesta passada; auditoria de look-ahead anterior vale) | ⏸️ pendente |
| 6 | Cockpit `get_status_operacoes` | 12 conferências (carteira real) | ver tabela abaixo | fórmula fechada das pernas cruas | ✅ 12/12 |
| — | OpLab `get_historical_data` | candles ITUB4 | 76 candles | 3 pares de candles **duplicados** (timestamps consecutivos idênticos) | ⚠️ qualidade de dado |

### Cockpit `get_status_operacoes` — 12/12 (detalhe)
5 travas 1×1 (4384/3040/2880/1545/2310), ITUB4 multi-leg (travado 2906,75 + descoberto 4684),
BBDC4 put ladder (5470), EGIE3 PUT_SECA (41425), SANB11 (15735), custo_zerar (−1640/−960).
Recálculo por `(Kv−Kc)·q − (eV−eC)·q` das pernas cruas. **Sinal do custo_zerar correto**
(negativo = débito pago) — a origem do bug anterior está sã.

---

## 🔴 Bug confirmado: `get_options_bs` ignora os parâmetros (ou erra 500)

**Prova reproduzível:** chamando a MESMA opção (ITUBH435) com `spotprice=43,14` e depois
`spotprice=48,00` — dois spots muito diferentes — a ferramenta devolveu resultado **idêntico**
(`price 1,9141`, `delta 0,640389`, ecoando `spotprice: 43,63`). Também ignorou o `vol=23,4`
informado (devolveu `volatility: 15,84`). Passando o `symbol` da ação (modo BS "puro"), retorna
**erro 500** (`ERR wrong number of arguments for 'mget'` — Redis a montante).

**Impacto:** qualquer análise "e se o spot fosse X / a vol fosse Y" via `get_options_bs` recebe
número **silenciosamente errado** (no what-if real S=43,14/vol=23,4 o correto seria ~1,29, não 1,91;
com S=48 seria ~5,27, e mesmo assim a ferramenta insiste em 1,91).

**Causa raiz:** a montante, na API OpLab `/market/options/bs`. Nosso MCP é **passthrough fiel** —
`build: pick(a, ["symbol","irate","type","spotprice","strike","premium","dtm","vol",...])` —
encaminha todos os parâmetros corretamente. O endpoint é que os descarta quando há `symbol` de opção.

**Verificação de fórmula:** mesmo com os inputs que a ferramenta ECOA (S=43,63, vol=15,84), o
BS de livro-texto dá 1,2503/δ0,6857 — que também **não** bate com o 1,9141/δ0,6404 devolvido.
Ou seja, além de ignorar os overrides, o resultado não reproduz BS canônico para os próprios
valores ecoados (provável day-count/modelo interno diferente ou dado stale).

### Correção — aguardando decisão do operador
Não é bug do nosso código (passthrough correto); é da API OpLab. Opções de correção **no nosso MCP**:
- **(A) Documentar** na descrição da ferramenta que overrides são ignorados/erram, para não induzir
  a erro (baixo risco, não restaura a função).
- **(B) Black-Scholes LOCAL:** quando o chamador passa `spotprice`/`vol` explícitos, o MCP calcula
  o BS por conta própria (fórmula já validada contra Hull — ver `scripts/bs_oracle.py`) em vez de
  encaminhar ao endpoint quebrado. Restaura o what-if de verdade. Muda o comportamento da ferramenta
  (arquiteturalmente relevante) → por isso a decisão fica com o operador.

---

## Independência de cada teste (por que não é circular)
- **#6 Cockpit:** fórmula fechada de payoff das pernas cruas, script separado
  (`patches/google-sheets-mcp/auditoria_status_operacoes.ts`) que **não importa** o engine.
- **#2 BS:** `scripts/bs_oracle.py`, auto-validado contra Hull (call 4,76/put 0,81/N(d1) 0,7791)
  e paridade put-call. Independente do provedor.
- **#4 IV Rank:** aritmética canônica sobre os próprios `iv_atual/iv_min/iv_max` (`scripts/iv_rank_check.py`).
- **#3 Estrutura:** valores/booleanos conferidos contra os extremos reais da série; detector de
  pivô independente em `scripts/pivots.py`.
- **#1 Quote:** cross-check `get_quote` × `get_stock` (mesmo provedor OpLab — independência de
  2ª fonte externa NÃO alcançada; declarado). O achado é a inconsistência do `spot_price` da chain.
- **#5 Backtest:** reconstrução de 3 ops + anti-look-ahead — não re-executado nesta passada.

## Pendências
- Decidir a correção do `get_options_bs` (A ou B).
- Executar #5 (backtest) com reconstrução manual de 3 operações quando houver janela.

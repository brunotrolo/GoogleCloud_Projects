# Auditoria independente dos MCPs (recálculo do zero)

**Data:** 2026-07-16 · **Princípio:** cada valor da ferramenta é conferido por um caminho
matematicamente **independente** (fórmula fechada de livro-texto ou fonte de dado alternativa),
nunca reimplementando a lógica interna da própria ferramenta. Bug óbvio e comprovado é
corrigido na hora.

## Estado da execução
No momento desta auditoria, os conectores **OpLab_API** e **Cockpit (Google Sheets)** estavam
**desconectados/aguardando reautorização**, e a sessão é não-interativa (sem OAuth). Consequência:

- ✅ **Teste #6 (Cockpit)** foi executado **100% independente**, usando o snapshot da carteira
  REAL capturado nesta mesma sessão (15/07) — não depende de conector ativo.
- ⏸️ **Testes #1–#5 (OpLab)** exigem chamada ao vivo. O **oráculo independente** de cada um foi
  construído e **auto-validado offline** (ver abaixo); a comparação final roda assim que o
  conector OpLab for reautorizado. **Nenhum número foi inventado.**

---

## Tabela de veredito

| # | Ferramenta | Conferência | Valor ferramenta | Recálculo independente | Veredito |
|---|---|---|---|---|---|
| 6 | Cockpit `get_status_operacoes` | BRAV3 21/08 risco_travado | 4384 | (17,88−15,88)·3200−(1,13−0,50)·3200 = **4384** | ✅ bate |
| 6 | " | BBAS3 21/08 risco_travado | 3040 | (22,40−17,40)·1000−(2,05−0,09)·1000 = **3040** | ✅ bate |
| 6 | " | BBDC4 21/08 risco_travado | 2880 | (19,56−15,56)·1200−(1,70−0,10)·1200 = **2880** | ✅ bate |
| 6 | " | VALE3 21/08 risco_travado | 1545 | (78,46−73,96)·500−(2,31−0,90)·500 = **1545** | ✅ bate |
| 6 | " | ITUB4 18/09 risco_travado | 2310 | (42,32−41,32)·3000−(0,83−0,60)·3000 = **2310** | ✅ bate |
| 6 | " | ITUB4 16/10 risco_travado (multi-leg) | 2906,75 | 6,79·700 − 2110·(700/800) = **2906,75** | ✅ bate |
| 6 | " | ITUB4 16/10 risco_descoberto (100 nuas) | 4684 | 46,84·100 = **4684** | ✅ bate |
| 6 | " | BBDC4 18/09 risco_travado (put ladder) | 5470 | 7000 − 1530 = **5470** | ✅ bate |
| 6 | " | EGIE3 21/08 desembolso (PUT_SECA) | 41425 | 31,50·800+32,75·200+32,25·300 = **41425** | ✅ bate |
| 6 | " | SANB11 16/10 desembolso (DESC_MISTA) | 15735 | 31,47·500 = **15735** | ✅ bate |
| 6 | " | BBAS3 21/08 **custo_zerar (sinal)** | −1640 | −1,68·1000+0,04·1000 = **−1640** (débito pago) | ✅ bate |
| 6 | " | BRAV3 21/08 custo_zerar | −960 | −0,45·3200+0,15·3200 = **−960** | ✅ bate |
| 2 | OpLab `get_options_bs` | oráculo BS (Hull) | — | call 4,76 / put 0,81 / Δ 0,7791 — **oráculo confiável** | ⏸️ aguarda conector |
| 1 | OpLab `get_quote` | spot vs 2ª fonte | — | (harness pronto) | ⏸️ aguarda conector |
| 3 | OpLab `get_analise_estrutura` | topos/fundos por pivô | — | detector de pivô independente pronto | ⏸️ aguarda conector |
| 4 | OpLab `get_iv_rank_historico` | (IVatual−IVmin)/(IVmax−IVmin)·100 | — | verificador aritmético pronto | ⏸️ aguarda conector |
| 5 | OpLab `get_backtest_*` | 3 ops reconstruídas + anti-look-ahead | — | plano definido | ⏸️ aguarda conector |

**Resumo Cockpit: 12 conferências, 0 divergências, 0 bugs.** O sinal do `custo_zerar` (origem do
bug anterior) está **correto** — negativo = débito pago pelo operador.

---

## Fonte de independência de cada teste (por que não é circular)

- **#6 Cockpit:** recálculo por fórmula fechada de payoff a partir das pernas **cruas**
  (strike/quantity/entry/last do JSON), num script separado que **não importa** o engine.
  Script: `patches/google-sheets-mcp/auditoria_status_operacoes.ts`.
- **#2 Black-Scholes:** fórmula fechada em Python (`scripts/bs_oracle.py`), auto-validada
  contra o exemplo publicado de **Hull** (S=42,K=40,r=10%,T=0,5,σ=20% → call 4,76, put 0,81,
  N(d1)=0,7791) e contra a **paridade put-call**. Independente do provedor do OpLab.
  Inclui teste do `spotprice` defasado (passar spot ≠ real e confirmar que a ferramenta usa o
  parâmetro, não um cache — problema já observado nesta conta).
- **#4 IV Rank:** aritmética canônica sobre os próprios `iv_atual/iv_min/iv_max` do output
  (`scripts/iv_rank_check.py`). Testa se a ferramenta aplica a fórmula que declara.
- **#3 Estrutura:** detector de pivô fractal de janela N sobre o OHLC bruto
  (`scripts/pivots.py`), do zero — confere valores/posições dos últimos topos/fundos e se os
  booleanos `topos_ascendentes/fundos_ascendentes` não estão invertidos.
- **#1 Quote:** cotação de 2ª fonte independente no mesmo instante (tolerância 0,5% por delay).
- **#5 Backtest:** reconstrução manual de 3 operações (entrada/vencimento via histórico) +
  verificação anti-look-ahead (nenhum dado da decisão vem de depois da data de entrada).

## Como completar a Parte B (quando o OpLab reconectar)
Reautorizar o conector **OpLab_API** (claude.ai → configurações de conectores). Depois, para os
5 tickers da amostra (ITUB4, CSAN3, BBDC4, VALE3, EQTL3):
1. `get_options_bs` → alimentar `scripts/bs_oracle.py` com os mesmos inputs → comparar preço/delta.
2. `get_iv_rank_historico` → `scripts/iv_rank_check.py` com iv_atual/min/max → comparar iv_rank.
3. `get_historical_data` → `scripts/pivots.py` → comparar topos/fundos com `get_analise_estrutura`.
4. `get_quote` → 2ª fonte → diferença < 0,5%.
5. `get_backtest_protocolo2` (ITUB4) → reconstruir 3 vencimentos à mão.

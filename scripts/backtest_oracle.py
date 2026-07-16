#!/usr/bin/env python3
"""
backtest_oracle.py — Reconstrução INDEPENDENTE de uma operação do get_backtest_estrutural.

Não importa nenhuma função do engine de backtest. Recalcula, por caminho próprio:
  (a) o resultado (WIN/LOSS, P&L) da operação — fórmula de payoff de trava/PUT nua;
  (b) o delta da PUT vendida na entrada — Black-Scholes (mesmo do bs_oracle.py);
  (c) GUARDA ANTI-LOOK-AHEAD: garante que o OHLC usado na decisão de entrada tem
      data_fim <= D0 (nenhum candle posterior à entrada entra na decisão).

Fluxo de uso (quando o conector OpLab voltar):
  1. get_backtest_estrutural(ticker="ITUB4", incluir_operacoes=true) → escolha 3 ops.
  2. Para cada op, get_historical_data(ITUB4, from=<início>, to=D0)  → entrada_csv (<= D0)
     e get_historical_data(ITUB4, from=D0, to=expiry)                → pega o close do vencimento.
  3. Rode este script com os parâmetros da op e confira contra o que o backtest reportou.

Exemplo:
  python3 backtest_oracle.py --d0 2025-08-15 --strike 40.0 --premio 1.20 \
     --spot_d0 41.5 --vol 0.28 --irate 0.145 --dte 25 --spot_venc 42.3 \
     --use_spread --strike_prot 37.0 --premio_prot 0.45 \
     --entrada_ohlc_csv candles_ate_d0.csv
"""
import argparse
import csv
import math


# ── BS (idêntico ao bs_oracle.py, para o delta da PUT na entrada) ──
def _norm_cdf(x): return 0.5 * (1 + math.erf(x / math.sqrt(2)))

def put_delta(S, K, r, T, sigma):
    if T <= 0 or sigma <= 0:
        return -1.0 if S < K else 0.0
    d1 = (math.log(S / K) + (r + 0.5 * sigma * sigma) * T) / (sigma * math.sqrt(T))
    return _norm_cdf(d1) - 1.0  # delta da PUT


# ── Payoff independente (trava de PUT ou PUT nua), por 1 ação × lote 100 ──
CONTRACT = 100

def resultado_operacao(strike, premio, spot_venc, use_spread, strike_prot=None, premio_prot=None):
    if use_spread:
        largura = strike - strike_prot
        premio_liq = premio - premio_prot
        if spot_venc >= strike:
            payoff = premio_liq
        elif spot_venc <= strike_prot:
            payoff = premio_liq - largura
        else:
            payoff = premio_liq - (strike - spot_venc)
        pl = round(payoff * CONTRACT, 2)
    else:
        if spot_venc > strike:
            pl = round(premio * CONTRACT, 2)
        else:
            pl = round((premio - (strike - spot_venc)) * CONTRACT, 2)
    return ("WIN" if pl >= 0 else "LOSS"), pl


def guarda_look_ahead(entrada_csv, d0):
    """Falha se qualquer candle usado na entrada tiver data > D0."""
    piores = []
    with open(entrada_csv) as f:
        for row in csv.reader(f):
            if not row:
                continue
            data = row[0].strip()
            if data[:4].isdigit() and data > d0:
                piores.append(data)
    if piores:
        raise SystemExit(f"🔴 LOOK-AHEAD: {len(piores)} candles posteriores a D0={d0} no CSV de entrada (ex: {piores[:3]})")
    return True


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--d0", required=True, help="data de entrada YYYY-MM-DD")
    ap.add_argument("--strike", type=float, required=True)
    ap.add_argument("--premio", type=float, required=True)
    ap.add_argument("--spot_d0", type=float, required=True, help="spot na entrada (para o delta)")
    ap.add_argument("--vol", type=float, required=True, help="vol implícita fração (0.28)")
    ap.add_argument("--irate", type=float, default=0.145)
    ap.add_argument("--dte", type=int, required=True)
    ap.add_argument("--spot_venc", type=float, required=True, help="close do ativo no vencimento (futuro, ok)")
    ap.add_argument("--use_spread", action="store_true")
    ap.add_argument("--strike_prot", type=float)
    ap.add_argument("--premio_prot", type=float)
    ap.add_argument("--entrada_ohlc_csv", help="CSV time,high,low[,close] com candles ATÉ D0 (guarda anti-look-ahead)")
    ap.add_argument("--delta_backtest", type=float, help="delta que o backtest reportou (p/ comparar)")
    a = ap.parse_args()

    if a.entrada_ohlc_csv:
        guarda_look_ahead(a.entrada_ohlc_csv, a.d0)
        print(f"✅ anti-look-ahead: nenhum candle > D0={a.d0} no CSV de entrada")

    delta = put_delta(a.spot_d0, a.strike, a.irate, a.dte / 365.0, a.vol)
    res, pl = resultado_operacao(a.strike, a.premio, a.spot_venc, a.use_spread, a.strike_prot, a.premio_prot)

    print(f"── Reconstrução independente da op D0={a.d0} ──")
    print(f"  delta PUT (BS, na entrada) = {delta:.3f}" + (f"  | backtest={a.delta_backtest}  {'✅' if a.delta_backtest is not None and abs(delta-a.delta_backtest)<0.05 else ''}" if a.delta_backtest is not None else ""))
    print(f"  resultado independente     = {res}  (P&L R$ {pl})")
    print(f"  → compare 'resultado' e a DIREÇÃO do P&L com o que o backtest reportou p/ esta op.")

#!/usr/bin/env python3
"""
pivots.py — Detector INDEPENDENTE de topos/fundos para auditar OpLab:get_analise_estrutura.

Algoritmo de pivô simples e explícito (fractal de janela N): um candle é TOPO se seu
high é o maior numa janela de ±N; FUNDO se seu low é o menor. Implementado do zero,
sem reusar a lógica interna da ferramenta. Recebe OHLC bruto (do get_historical_data)
via CSV/JSON e imprime os últimos topos/fundos, além dos booleanos topos_ascendentes /
fundos_ascendentes (último > penúltimo) para conferir se a ferramenta não inverteu a comparação.

Entrada: JSON de candles no stdin — lista de objetos com 'time','high','low' (ou
'h','l'), OU CSV 'time,high,low'. N padrão = 2.
    cat candles.json | python3 pivots.py --n 2
"""
import argparse
import json
import sys


def load_candles(text: str):
    text = text.strip()
    out = []
    if text.startswith("[") or text.startswith("{"):
        data = json.loads(text)
        if isinstance(data, dict):
            for k in ("data", "candles", "results"):
                if k in data:
                    data = data[k]
                    break
        for c in data:
            hi = c.get("high", c.get("h"))
            lo = c.get("low", c.get("l"))
            t = c.get("time", c.get("t", c.get("date")))
            if hi is not None and lo is not None:
                out.append({"t": t, "high": float(hi), "low": float(lo)})
    else:
        for line in text.splitlines():
            p = [x.strip() for x in line.split(",")]
            if len(p) >= 3:
                try:
                    out.append({"t": p[0], "high": float(p[1]), "low": float(p[2])})
                except ValueError:
                    continue  # cabeçalho
    return out


def pivots(candles, n=2):
    topos, fundos = [], []
    for i in range(n, len(candles) - n):
        janela = candles[i - n:i + n + 1]
        c = candles[i]
        if c["high"] == max(x["high"] for x in janela):
            topos.append({"i": i, "t": c["t"], "valor": c["high"]})
        if c["low"] == min(x["low"] for x in janela):
            fundos.append({"i": i, "t": c["t"], "valor": c["low"]})
    return topos, fundos


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=2, help="meia-janela do pivô (padrão 2)")
    a = ap.parse_args()
    candles = load_candles(sys.stdin.read())
    if len(candles) < 2 * a.n + 1:
        print(f"🔴 candles insuficientes ({len(candles)}) para janela n={a.n}")
        raise SystemExit(1)
    topos, fundos = pivots(candles, a.n)
    print(f"candles={len(candles)}  n={a.n}")
    print("últimos 3 topos:", [(x["t"], x["valor"]) for x in topos[-3:]])
    print("últimos 3 fundos:", [(x["t"], x["valor"]) for x in fundos[-3:]])
    if len(topos) >= 2:
        asc = topos[-1]["valor"] > topos[-2]["valor"]
        print(f"topos_ascendentes (independente) = {asc}  (último {topos[-1]['valor']} > penúltimo {topos[-2]['valor']})")
    if len(fundos) >= 2:
        asc = fundos[-1]["valor"] > fundos[-2]["valor"]
        print(f"fundos_ascendentes (independente) = {asc}  (último {fundos[-1]['valor']} > penúltimo {fundos[-2]['valor']})")
    print("→ compare topos/fundos e os booleanos com get_analise_estrutura (±1 candle é aceitável)")

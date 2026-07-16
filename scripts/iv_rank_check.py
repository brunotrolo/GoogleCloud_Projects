#!/usr/bin/env python3
"""
iv_rank_check.py — Verificador INDEPENDENTE do IV Rank (OpLab:get_iv_rank_historico).

Fórmula canônica: IV_Rank = (IV_atual − IV_min) / (IV_max − IV_min) × 100.
A ferramenta já devolve iv_atual, iv_min_periodo, iv_max_periodo E iv_rank.
Este script recalcula o iv_rank a partir dos 3 primeiros e compara com o 4º —
testa se a ferramenta aplica corretamente a PRÓPRIA fórmula declarada. Aritmética
pura: exige bater exato (tolerância mínima de arredondamento).

Uso (com os números que a ferramenta devolver):
    python3 iv_rank_check.py --iv_atual 26.7 --iv_min 18.9 --iv_max 41.2 --iv_rank_ferramenta 34.9
"""
import argparse


def iv_rank(iv_atual: float, iv_min: float, iv_max: float) -> float:
    if iv_max == iv_min:
        return float("nan")
    return (iv_atual - iv_min) / (iv_max - iv_min) * 100.0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--iv_atual", type=float, required=True)
    ap.add_argument("--iv_min", type=float, required=True)
    ap.add_argument("--iv_max", type=float, required=True)
    ap.add_argument("--iv_rank_ferramenta", type=float, required=True)
    a = ap.parse_args()
    indep = iv_rank(a.iv_atual, a.iv_min, a.iv_max)
    diff = abs(indep - a.iv_rank_ferramenta)
    ok = diff <= 0.1
    print(f"IV Rank independente = ({a.iv_atual}−{a.iv_min})/({a.iv_max}−{a.iv_min})·100 = {indep:.2f}")
    print(f"IV Rank ferramenta   = {a.iv_rank_ferramenta:.2f}")
    print(f"veredito: {'✅ bate' if ok else '🔴 DIVERGE'} (Δ={diff:.3f})")
    raise SystemExit(0 if ok else 1)

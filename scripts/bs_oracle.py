#!/usr/bin/env python3
"""
bs_oracle.py — Oráculo INDEPENDENTE de Black-Scholes para auditar OpLab:get_options_bs.

Não importa nem copia nada do servidor OpLab. É a fórmula fechada de livro-texto.
Auto-validado contra o exemplo canônico de Hull (Options, Futures and Other
Derivatives): S0=42, K=40, r=10%, sigma=20%, T=0.5 -> call=4.76, put=0.81,
delta_call=N(d1)=0.7791. Se este self-test passar, o oráculo é confiável para
comparar com o output da ferramenta quando os conectores voltarem.

Uso p/ auditar 1 opção:
    python3 bs_oracle.py --S 43.14 --K 43.00 --r 0.15 --T_days 30 --sigma 0.34 --tipo CALL
Depois compare 'preco'/'delta' com o get_options_bs (mesmos inputs).
"""
import argparse
import math


def _norm_cdf(x: float) -> float:
    # CDF da normal padrão via erf (sem dependências externas).
    return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))


def black_scholes(S: float, K: float, r: float, T: float, sigma: float, tipo: str, q: float = 0.0):
    """Preço e gregas por fórmula fechada. T em ANOS, r/sigma/q em fração (0.10 = 10%)."""
    tipo = tipo.upper()
    if T <= 0 or sigma <= 0:
        # limite: valor intrínseco, delta degrau
        intr = max(0.0, (S - K) if tipo == "CALL" else (K - S))
        return {"preco": intr, "delta": float("nan"), "d1": float("nan"), "d2": float("nan")}
    d1 = (math.log(S / K) + (r - q + 0.5 * sigma * sigma) * T) / (sigma * math.sqrt(T))
    d2 = d1 - sigma * math.sqrt(T)
    disc_r = math.exp(-r * T)
    disc_q = math.exp(-q * T)
    if tipo == "CALL":
        preco = S * disc_q * _norm_cdf(d1) - K * disc_r * _norm_cdf(d2)
        delta = disc_q * _norm_cdf(d1)
    else:
        preco = K * disc_r * _norm_cdf(-d2) - S * disc_q * _norm_cdf(-d1)
        delta = -disc_q * _norm_cdf(-d1)
    vega = S * disc_q * math.sqrt(T) * (1.0 / math.sqrt(2 * math.pi)) * math.exp(-0.5 * d1 * d1)
    return {"preco": preco, "delta": delta, "d1": d1, "d2": d2, "vega_1pct": vega / 100.0}


def _self_test() -> bool:
    # Hull, exemplo clássico. Valores publicados: call 4.76, put 0.81, N(d1) 0.7791.
    c = black_scholes(42, 40, 0.10, 0.5, 0.20, "CALL")
    p = black_scholes(42, 40, 0.10, 0.5, 0.20, "PUT")
    ok = (abs(c["preco"] - 4.76) < 0.01 and abs(p["preco"] - 0.81) < 0.01
          and abs(c["delta"] - 0.7791) < 0.001)
    print("── SELF-TEST (Hull S=42,K=40,r=10%,T=0.5,σ=20%) ──")
    print(f"  call = {c['preco']:.4f}  (esperado 4.76)   {'✅' if abs(c['preco']-4.76)<0.01 else '🔴'}")
    print(f"  put  = {p['preco']:.4f}  (esperado 0.81)   {'✅' if abs(p['preco']-0.81)<0.01 else '🔴'}")
    print(f"  delta_call = N(d1) = {c['delta']:.4f}  (esperado 0.7791)   {'✅' if abs(c['delta']-0.7791)<0.001 else '🔴'}")
    # Paridade put-call: C - P = S - K*e^{-rT}
    lhs = c["preco"] - p["preco"]
    rhs = 42 - 40 * math.exp(-0.10 * 0.5)
    print(f"  paridade put-call: C−P={lhs:.4f} vs S−K·e^(−rT)={rhs:.4f}   {'✅' if abs(lhs-rhs)<1e-6 else '🔴'}")
    print(f"  => oráculo {'CONFIÁVEL' if ok else 'FALHOU'}\n")
    return ok


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--S", type=float); ap.add_argument("--K", type=float)
    ap.add_argument("--r", type=float, default=0.15, help="taxa livre de risco (fração)")
    ap.add_argument("--T_days", type=float, help="dias corridos até o vencimento")
    ap.add_argument("--sigma", type=float, help="vol implícita (fração, 0.34=34%)")
    ap.add_argument("--tipo", default="CALL", choices=["CALL", "PUT"])
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()

    passed = _self_test()
    if a.S and a.K and a.T_days and a.sigma:
        res = black_scholes(a.S, a.K, a.r, a.T_days / 365.0, a.sigma, a.tipo)
        print(f"── BS independente (T={a.T_days}d corridos = {a.T_days/365.0:.4f}a) ──")
        print(f"  preco_teorico = {res['preco']:.4f}")
        print(f"  delta         = {res['delta']:.4f}")
        print(f"  (compare com get_options_bs usando EXATAMENTE estes inputs)")
    raise SystemExit(0 if passed else 1)

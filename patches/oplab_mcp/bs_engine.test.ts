// Testes do motor BS local. Rodar:
//   node --experimental-strip-types bs_engine.test.ts
import assert from 'node:assert';
import { blackScholes, precificarLocalSePossivel } from './bs_engine.ts';

let p = 0;
const t = (n: string, f: () => void) => { f(); p++; console.log(`  ✓ ${n}`); };
const near = (a: number, b: number, tol: number) => Math.abs(a - b) <= tol;

console.log('bs_engine — testes\n');

// Oráculo canônico: Hull (S=42,K=40,r=10%,T=0.5,σ=20%) → call 4.76, put 0.81, N(d1)=0.7791
t('Hull call/put/delta', () => {
  const c = blackScholes({ S: 42, K: 40, r: 0.10, T: 0.5, sigma: 0.20, tipo: 'CALL' });
  const put = blackScholes({ S: 42, K: 40, r: 0.10, T: 0.5, sigma: 0.20, tipo: 'PUT' });
  assert.ok(near(c.price, 4.76, 0.01), `call=${c.price}`);
  assert.ok(near(put.price, 0.81, 0.01), `put=${put.price}`);
  assert.ok(near(c.delta, 0.7791, 0.001), `delta=${c.delta}`);
});

// Paridade put-call: C − P = S − K·e^(−rT)
t('paridade put-call', () => {
  const c = blackScholes({ S: 42, K: 40, r: 0.10, T: 0.5, sigma: 0.20, tipo: 'CALL' });
  const put = blackScholes({ S: 42, K: 40, r: 0.10, T: 0.5, sigma: 0.20, tipo: 'PUT' });
  assert.ok(near(c.price - put.price, 42 - 40 * Math.exp(-0.10 * 0.5), 1e-4));
});

// What-if real do caso auditado (ITUBH435): S=43.14, K=43.22, r=14.15%, dtm=27, σ=23.4%
// Oráculo Python (bs_oracle.py) deu price 1.2854 / delta 0.5664.
t('what-if ITUBH435 (o que a ferramenta DEVERIA ter devolvido)', () => {
  const out = precificarLocalSePossivel({ spotprice: 43.14, strike: 43.22, vol: 23.4, irate: 14.15, dtm: 27, type: 'CALL' })!;
  assert.ok(out, 'deveria calcular local');
  assert.ok(near(out.price as number, 1.2854, 0.01), `price=${out.price}`);
  assert.ok(near(out.delta as number, 0.5664, 0.005), `delta=${out.delta}`);
  assert.strictEqual(out.metodo, 'black_scholes_local_europeu');
});

// Spot deslocado (48) tem que mudar MUITO (prova que usamos o parâmetro): ~5.27
t('spot deslocado muda o preço (o bug era NÃO mudar)', () => {
  const out = precificarLocalSePossivel({ spotprice: 48, strike: 43.22, vol: 23.4, irate: 14.15, dtm: 27, type: 'CALL' })!;
  assert.ok(near(out.price as number, 5.2699, 0.02), `price=${out.price}`);
  assert.ok((out.delta as number) > 0.9, `delta=${out.delta}`);
});

// vol aceita % (23.4) ou fração (0.234) — mesmo resultado
t('vol em % ou fração dá o mesmo', () => {
  const a = precificarLocalSePossivel({ spotprice: 43.14, strike: 43.22, vol: 23.4, irate: 14.15, dtm: 27, type: 'CALL' })!;
  const b = precificarLocalSePossivel({ spotprice: 43.14, strike: 43.22, vol: 0.234, irate: 0.1415, dtm: 27, type: 'CALL' })!;
  assert.ok(near(a.price as number, b.price as number, 1e-6));
});

// Sem inputs suficientes → null (chamador faz passthrough para o endpoint)
t('sem spotprice/strike/vol → passthrough (null)', () => {
  assert.strictEqual(precificarLocalSePossivel({ symbol: 'ITUBH435', irate: 14.15, type: 'CALL' }), null);
  assert.strictEqual(precificarLocalSePossivel({ spotprice: 43, strike: 43, vol: 20, irate: 14, type: 'CALL' }), null, 'sem prazo → null');
});

console.log(`\n✅ ${p} testes passaram.`);

// AUDITORIA INDEPENDENTE do get_status_operacoes (Cockpit).
// "Lado ferramenta"  = buildStatusOperacoes (a MESMA lógica deployada).
// "Lado independente" = recálculo do ZERO a partir das pernas cruas, por fórmula
//   fechada, SEM importar/olhar a lógica interna do engine. Só aritmética explícita.
// Dados = carteira REAL (snapshot get_cockpit_ativas de 2026-07-15).
import { buildStatusOperacoes } from './status_engine.ts';

const HOJE = new Date('2026-07-16T00:00:00.000Z');
const PAT = 150000;

const L = (T: string, OT: string, S: string, TP: string, Q: string, K: string, SP: string, EN: string, LA: string, EX: string, PL: string) =>
  ({ STATUS: 'ATIVO', TICKER: T, OPTION_TICKER: OT, SIDE: S, OPTION_TYPE: TP, QUANTITY: Q, STRIKE: K, SPOT: SP, ENTRY_PRICE: EN, LAST_PREMIUM: LA, EXPIRY: EX, PL_VALUE: PL });

const rows = [
  L('SANB11','SANBJ349','COMPRA','CALL','400','33.47','27.06','2.29','0.20','16/10/2026','836'),
  L('SANB11','SANBV329','VENDA','PUT','500','31.47','27.06','2.57','4.00','16/10/2026','-715'),
  L('FLRY3','FLRYT167','VENDA','PUT','1000','16.73','16.50','0.68','0.59','21/08/2026','93.72'),
  L('FLRY3','FLRYH172','COMPRA','CALL','600','17.23','16.50','0.69','1.20','21/08/2026','-307.69'),
  L('VALE3','VALEI896','COMPRA','CALL','300','89.65','74.58','2.85','0.32','18/09/2026','759'),
  L('VALE3','VALEU806','VENDA','PUT','300','80.65','74.58','3.70','6.02','18/09/2026','-696'),
  L('BRAV3','BRAVT160','COMPRA','PUT','3200','15.88','19.91','0.50','0.15','21/08/2026','1120'),
  L('BRAV3','BRAVT180','VENDA','PUT','3200','17.88','19.91','1.13','0.45','21/08/2026','2176'),
  L('ITUB4','ITUBV475','VENDA','PUT','100','46.84','43.14','5.00','5.00','16/10/2026','0'),
  L('ITUB4','ITUBV403','COMPRA','PUT','700','40.05','43.14','1.80','0.80','16/10/2026','700'),
  L('ITUB4','ITUBV475b','VENDA','PUT','700','46.84','43.14','4.10','5.00','16/10/2026','-630'),
  L('EGIE3','EGIET319','VENDA','PUT','800','31.50','30.55','0.57','1.59','21/08/2026','-816'),
  L('BBAS3','BBAST225','VENDA','PUT','1000','22.40','20.56','2.05','1.68','21/08/2026','370'),
  L('BBAS3','BBAST175','COMPRA','PUT','1000','17.40','20.56','0.09','0.04','21/08/2026','50'),
  L('BBDC4','BBDCT211','VENDA','PUT','1200','19.56','18.57','1.70','1.01','21/08/2026','828'),
  L('BBDC4','BBDCT162','COMPRA','PUT','1200','15.56','18.57','0.10','0.02','21/08/2026','96'),
  L('BBDC4','BBDCT181','VENDA','PUT','200','17.56','18.57','1.00','0.20','24/08/2026','160'),
  L('BBDC4','BBDCH201','COMPRA','CALL','200','18.56','18.57','1.55','0.76','24/08/2026','158'),
  L('VALE3','VALET739','COMPRA','PUT','500','73.96','74.58','0.90','1.77','21/08/2026','-435'),
  L('VALE3','VALET784','VENDA','PUT','500','78.46','74.58','2.31','4.18','21/08/2026','-935'),
  L('EGIE3','EGIET327','VENDA','PUT','200','32.75','30.55','1.67','2.36','21/08/2026','-138'),
  L('EGIE3','EGIET322','VENDA','PUT','300','32.25','30.55','1.39','2.04','21/08/2026','-195'),
  L('BBDC4','BBDCU181','COMPRA','PUT','4000','16.83','18.57','0.17','0.17','18/09/2026','0'),
  L('BBDC4','BBDCU23','VENDA','PUT','4000','17.83','18.57','0.35','0.36','18/09/2026','-40'),
  L('ITUB4','ITUBU429','VENDA','PUT','3000','42.32','43.14','0.83','0.78','18/09/2026','150'),
  L('ITUB4','ITUBU419','COMPRA','PUT','3000','41.32','43.14','0.60','0.63','18/09/2026','-90'),
  L('BBDC4','BBDCU21','COMPRA','PUT','3000','17.33','18.57','0.27','0.24','18/09/2026','90'),
  L('BBDC4','BBDCU196','VENDA','PUT','3000','18.33','18.57','0.54','0.54','18/09/2026','0'),
];

const tool = buildStatusOperacoes(rows, { patrimonio: PAT }, HOJE);
const byKey = (t: string, d: string) => tool.estruturas.find((e: any) => e.ticker === t && e.due_date === d);
const r2 = (n: number) => Math.round(n * 100) / 100;
const linhas: Array<[string, string, number | string, number | string, string]> = [];
const cmp = (campo: string, ferr: number, indep: number, tol = 0.01) => {
  const ok = Math.abs(ferr - indep) <= tol;
  linhas.push([campo, '', r2(ferr), r2(indep), ok ? '✅ bate' : '🔴 DIVERGE']);
  return ok;
};

console.log('════ AUDITORIA INDEPENDENTE — get_status_operacoes (carteira real 15/07) ════\n');

// ── TRAVAS 1×1: risco = (Kv−Kc)×q − (entryV−entryC)×q  [fórmula fechada, pernas cruas] ──
const travas1x1 = [
  { t: 'BRAV3', d: '21/08/2026', Kv: 17.88, Kc: 15.88, q: 3200, eV: 1.13, eC: 0.50 },
  { t: 'BBAS3', d: '21/08/2026', Kv: 22.40, Kc: 17.40, q: 1000, eV: 2.05, eC: 0.09 },
  { t: 'BBDC4', d: '21/08/2026', Kv: 19.56, Kc: 15.56, q: 1200, eV: 1.70, eC: 0.10 },
  { t: 'VALE3', d: '21/08/2026', Kv: 78.46, Kc: 73.96, q: 500,  eV: 2.31, eC: 0.90 },
  { t: 'ITUB4', d: '18/09/2026', Kv: 42.32, Kc: 41.32, q: 3000, eV: 0.83, eC: 0.60 },
];
console.log('── TRAVA_ALTA 1×1 · risco_maximo_travado = (Kv−Kc)·q − (eV−eC)·q ──');
for (const x of travas1x1) {
  const indep = (x.Kv - x.Kc) * x.q - (x.eV - x.eC) * x.q;
  const e = byKey(x.t, x.d);
  console.log(`  ${x.t} ${x.d}: (${x.Kv}−${x.Kc})·${x.q} − (${x.eV}−${x.eC})·${x.q} = ${r2(indep)}`);
  cmp(`${x.t} ${x.d} risco_travado`, e.risco_maximo_travado, indep);
}

// ── TRAVA multi-strike ITUB4 Oct (800 vend / 700 prot): 100 descoberto ──
console.log('\n── ITUB4 16/10 (multi-leg, 800 vend / 700 prot) ──');
{
  // casada 700 @ Kv=46.84 vs Kc=40.05 ; largura 6.79 × 700 = 4753
  // crédito líquido total = (5.00·100 + 4.10·700) − 1.80·700 = 3370 − 1260 = 2110
  // rateado à casada: 2110 × 700/800 = 1846.25 → travado = 4753 − 1846.25 = 2906.75
  const larguraBruta = (46.84 - 40.05) * 700;
  const creditoTot = (5.00 * 100 + 4.10 * 700) - 1.80 * 700;
  const creditoCasado = creditoTot * (700 / 800);
  const indepTravado = larguraBruta - creditoCasado;
  const indepDescoberto = 46.84 * 100; // 100 descobertas × pior strike vendido
  const e = byKey('ITUB4', '16/10/2026');
  console.log(`  travado = 6.79·700 − 2110·(700/800) = ${r2(larguraBruta)} − ${r2(creditoCasado)} = ${r2(indepTravado)}`);
  console.log(`  descoberto = 46.84·100 = ${r2(indepDescoberto)}`);
  cmp('ITUB4 16/10 risco_travado', e.risco_maximo_travado, indepTravado);
  cmp('ITUB4 16/10 risco_descoberto', e.risco_adicional_descoberto, indepDescoberto);
}

// ── TRAVA multi-strike BBDC4 Sep (put ladder 7000/7000) = soma de 2 verticais ──
console.log('\n── BBDC4 18/09 (put ladder: 2 verticais empilhados) ──');
{
  // vertical A: 18.33/17.33 × 3000 ; vertical B: 17.83/16.83 × 4000 ; ambos largura 1.00
  // largura bruta = 1·3000 + 1·4000 = 7000
  // crédito líq = (0.54·3000+0.35·4000) − (0.27·3000+0.17·4000) = 3020 − 1490 = 1530
  const larguraBruta = (18.33 - 17.33) * 3000 + (17.83 - 16.83) * 4000;
  const credito = (0.54 * 3000 + 0.35 * 4000) - (0.27 * 3000 + 0.17 * 4000);
  const indep = larguraBruta - credito;
  const e = byKey('BBDC4', '18/09/2026');
  console.log(`  travado = 7000 − 1530 = ${r2(indep)}`);
  cmp('BBDC4 18/09 risco_travado', e.risco_maximo_travado, indep);
}

// ── PUT_SECA EGIE3 (3 vendas nuas) · desembolso = ΣKv·q ──
console.log('\n── PUT_SECA / DESCOBERTA_MISTA · desembolso = ΣKv·q ──');
{
  const indep = 31.50 * 800 + 32.75 * 200 + 32.25 * 300;
  const e = byKey('EGIE3', '21/08/2026');
  console.log(`  EGIE3 21/08: 31.50·800 + 32.75·200 + 32.25·300 = ${r2(indep)}`);
  cmp('EGIE3 21/08 desembolso', e.desembolso_se_exercido_total, indep);
  console.log(`    tipo ferramenta = ${e.tipo} (esperado PUT_SECA)  ${e.tipo === 'PUT_SECA' ? '✅' : '🔴'}`);
}
{
  const indep = 31.47 * 500; // SANB11: PUT vendida 500@31.47 (CALL comprada não protege)
  const e = byKey('SANB11', '16/10/2026');
  console.log(`  SANB11 16/10: 31.47·500 = ${r2(indep)}  tipo=${e.tipo}`);
  cmp('SANB11 16/10 desembolso', e.desembolso_se_exercido_total, indep);
}

// ── SINAL do custo_zerar (origem do bug) · fechar VENDA paga(−), COMPRA recebe(+) ──
console.log('\n── custo_zerar · convenção: fechar VENDA = −last·q (paga) ; COMPRA = +last·q (recebe) ──');
{
  // BBAS3: recompra vendida 1.68·1000 (−1680) + vende proteção 0.04·1000 (+40) = −1640
  const indep = -(1.68 * 1000) + (0.04 * 1000);
  const e = byKey('BBAS3', '21/08/2026');
  console.log(`  BBAS3 21/08: −1.68·1000 + 0.04·1000 = ${r2(indep)}  (negativo = débito pago ✓)`);
  cmp('BBAS3 21/08 custo_zerar', e.custo_zerar, indep);
}
{
  // BRAV3: −0.45·3200 + 0.15·3200 = −960
  const indep = -(0.45 * 3200) + (0.15 * 3200);
  const e = byKey('BRAV3', '21/08/2026');
  console.log(`  BRAV3 21/08: −0.45·3200 + 0.15·3200 = ${r2(indep)}`);
  cmp('BRAV3 21/08 custo_zerar', e.custo_zerar, indep);
}

const bugs = linhas.filter((l) => String(l[4]).includes('🔴')).length;
console.log(`\n════ RESULTADO: ${linhas.length} conferências, ${bugs} divergência(s) ════`);
console.log(JSON.stringify(linhas.map(([c, , f, i, v]) => ({ conferencia: c, ferramenta: f, independente: i, veredito: v })), null, 0));

// Testes do núcleo puro da whitelist. Rodar:
//   node --experimental-strip-types whitelist_source.test.ts
import assert from 'node:assert';
import { parseTickersCSV, fetchWhitelistCSV, WHITELIST_FALLBACK } from './whitelist_source.ts';

let passed = 0;
function t(nome: string, fn: () => void | Promise<void>) {
  return Promise.resolve(fn()).then(() => { passed++; console.log(`  ✓ ${nome}`); });
}

console.log('whitelist_source — testes\n');

await t('fallback tem 26 ativos e inclui os adicionados / exclui os removidos', () => {
  assert.strictEqual(WHITELIST_FALLBACK.length, 26);
  for (const add of ['EQTL3', 'EGIE3', 'BPAC11', 'SUZB3']) assert.ok(WHITELIST_FALLBACK.includes(add), `faltou ${add}`);
  for (const rem of ['COGN3', 'CMIN3', 'CPLE6', 'ELET3']) assert.ok(!WHITELIST_FALLBACK.includes(rem), `deveria ter saído: ${rem}`);
});

await t('parseTickersCSV com cabeçalho TICKER', () => {
  const csv = 'TICKER,NOME\nVALE3,Vale ON\nPETR4,Petrobras PN\nBPAC11,BTG\n';
  assert.deepStrictEqual(parseTickersCSV(csv), ['VALE3', 'PETR4', 'BPAC11']);
});

await t('parseTickersCSV sem cabeçalho (1ª coluna)', () => {
  const csv = 'VALE3\nPETR4\nSANB11\n';
  assert.deepStrictEqual(parseTickersCSV(csv), ['VALE3', 'PETR4', 'SANB11']);
});

await t('parseTickersCSV ignora lixo, aspas, espaços e duplicatas', () => {
  const csv = 'TICKER\n"VALE3"\n  PETR4  \n\nnão-ticker\nVALE3\n123\n';
  assert.deepStrictEqual(parseTickersCSV(csv), ['VALE3', 'PETR4']);
});

await t('fetchWhitelistCSV sucesso via fetch injetado', async () => {
  const fakeFetch = (async () => ({ ok: true, status: 200, text: async () => 'TICKER\nVALE3\nPETR4\nITUB4\nBBAS3\nBBDC4\nEGIE3\n' })) as unknown as typeof fetch;
  const out = await fetchWhitelistCSV('http://x', fakeFetch);
  assert.deepStrictEqual(out, ['VALE3', 'PETR4', 'ITUB4', 'BBAS3', 'BBDC4', 'EGIE3']);
});

await t('fetchWhitelistCSV rejeita CSV curto/quebrado (guarda contra fallback silencioso)', async () => {
  const fakeFetch = (async () => ({ ok: true, status: 200, text: async () => 'TICKER\nVALE3\n' })) as unknown as typeof fetch;
  await assert.rejects(() => fetchWhitelistCSV('http://x', fakeFetch), /≥5|apenas/);
});

await t('fetchWhitelistCSV rejeita HTTP não-ok', async () => {
  const fakeFetch = (async () => ({ ok: false, status: 404, text: async () => '' })) as unknown as typeof fetch;
  await assert.rejects(() => fetchWhitelistCSV('http://x', fakeFetch), /HTTP 404/);
});

console.log(`\n✅ ${passed} testes passaram.`);

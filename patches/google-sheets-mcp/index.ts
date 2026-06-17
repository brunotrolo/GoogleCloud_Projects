import express from 'express';
import { google } from 'googleapis';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import path from 'path';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 8080;
const SPREADSHEET_ID = process.env.SPREADSHEET_ID;

const auth = new google.auth.GoogleAuth({
  keyFile: path.join(process.cwd(), 'config', 'credentials.json'),
  scopes: ['https://www.googleapis.com/auth/spreadsheets.readonly'],
});

const sheets = google.sheets({ version: 'v4', auth });

const mcpServer = new Server(
  { name: 'oplab-sheets-portfolio', version: '1.0.0' },
  { capabilities: { tools: {} } }
);

// Streamable HTTP stateless: cada chamada responde e FECHA — sem conexão
// pendurada, então a CPU só é cobrada durante o processamento da requisição.
let connected = false;
app.post('/mcp', express.json(), async (req, res) => {
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
  res.on('close', () => {
    transport.close();
  });
  try {
    if (connected) {
      try { await mcpServer.close(); } catch { /* ignore */ }
    }
    await mcpServer.connect(transport);
    connected = true;
    await transport.handleRequest(req, res, req.body);
  } catch (e) {
    console.error('Erro MCP:', e);
    if (!res.headersSent) {
      res.status(500).json({ jsonrpc: '2.0', error: { code: -32603, message: 'Internal error' }, id: null });
    }
  }
});

// Parser tolerante a formatos BR (1.234,56), US (1,234.56), R$, % e (x) negativo.
// Detecta o formato pela posição do separador mais à direita: ele é o decimal.
function parseNumberBR(raw: any): number {
  if (raw === undefined || raw === null) return 0;
  let s = String(raw).trim();
  if (s === '') return 0;

  let negative = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.slice(1, -1);
  }
  s = s.replace(/R\$/gi, '').replace(/%/g, '').replace(/\s/g, '');

  const lastDot = s.lastIndexOf('.');
  const lastComma = s.lastIndexOf(',');

  if (lastDot >= 0 && lastComma >= 0) {
    if (lastComma > lastDot) {
      // BR: 1.234,56 — . é milhar, , é decimal
      s = s.replace(/\./g, '').replace(',', '.');
    } else {
      // US: 1,234.56 — , é milhar, . é decimal
      s = s.replace(/,/g, '');
    }
  } else if (lastComma >= 0) {
    // Só vírgula: assume decimal BR
    s = s.replace(',', '.');
  }
  // Só ponto ou sem separador: parse direto

  const n = parseFloat(s);
  if (Number.isNaN(n)) return 0;
  return negative ? -n : n;
}

mcpServer.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: 'get_cockpit_ativas',
        description: 'Retorna posições ATIVAS da aba COCKPIT cortando as 9 primeiras linhas. Cada linha inclui todos os campos da aba — entre eles STATUS e TRADE_MONTH.',
        inputSchema: { type: 'object', properties: {} }
      },
      {
        name: 'get_cockpit_historico',
        description: 'Retorna posições com STATUS = ENCERRADO ou EXERCIDA da aba COCKPIT. Aceita filtros opcionais "trade_month" (substring, ex: "5" casa "2024-05") e "ticker" (match exato, ex: "EMBJ3").',
        inputSchema: {
          type: 'object',
          properties: {
            trade_month: { type: 'string', description: 'Filtro opcional sobre TRADE_MONTH (substring).' },
            ticker: { type: 'string', description: 'Filtro opcional sobre TICKER (match exato).' }
          }
        }
      },
      {
        name: 'get_resumo_mensal',
        description: 'Resumo agregado por TRADE_MONTH da aba COCKPIT. Prêmios (max_gain_venda, max_gain_compra, premio_liquido) somam TODAS as operações do mês (ativas + encerradas + exercidas) — refletem a exposição contratada. P&L realizado e contagens consideram apenas as encerradas/exercidas (qtde_encerradas) e ativas (qtde_ativas) separadamente. Ordenado cronologicamente.',
        inputSchema: { type: 'object', properties: {} }
      },
      {
        name: 'get_cockpit_por_ativo',
        description: 'Retorna todas as posições da aba COCKPIT (ativas + encerradas + exercidas) com TICKER igual ao parâmetro fornecido. Útil para ver histórico completo de um ativo.',
        inputSchema: {
          type: 'object',
          properties: {
            ticker: { type: 'string', description: 'Código do ativo (obrigatório). Ex: "EMBJ3".' }
          },
          required: ['ticker']
        }
      },
      {
        name: 'get_resumo_por_ativo',
        description: 'Resumo histórico consolidado de um ticker da aba COCKPIT. Inclui total de operações (por status), prêmio bruto de vendas, custo de proteções, prêmio líquido total, P&L realizado, P&L MTM das ativas, win rate, maior ganho e maior perda. Também devolve as posições ativas do ativo.',
        inputSchema: {
          type: 'object',
          properties: {
            ticker: { type: 'string', description: 'Código do ativo (obrigatório). Ex: "EMBJ3".' }
          },
          required: ['ticker']
        }
      },
      {
        name: 'get_dashboard_mensal',
        description: 'Dashboard de performance para um mês específico da aba COCKPIT. Prêmios (premio_bruto_vendas, custo_protecoes, premio_liquido) somam TODAS as operações do mês (ativas + encerradas + exercidas) — refletem a exposição contratada. P&L realizado, win rate, melhor/pior operação consideram apenas as encerradas/exercidas (performance realizada). Inclui também comparativo com mês anterior (variação % do prêmio líquido total) e quebra por ticker.',
        inputSchema: {
          type: 'object',
          properties: {
            mes: { type: 'string', description: 'Mês a consultar (obrigatório). Casado com TRADE_MONTH. Ex: "5".' },
            ano: { type: 'string', description: 'Ano para o período/comparativo. Opcional — usa o ano atual se omitido. Ex: "2026".' }
          },
          required: ['mes']
        }
      },
      {
        name: 'get_alertas_posicoes',
        description: 'Avalia as posições ATIVAS de venda da aba COCKPIT e retorna alertas classificados por nível de risco (CRITICO, ALERTA, AVISO). Critérios consideram DTE (dias até o vencimento, calculado a partir de EXPIRY vs. hoje), MONEYNESS (ITM/ATM) e relação PL_VALUE / MAX_GAIN. Cada alerta inclui ação sugerida.',
        inputSchema: { type: 'object', properties: {} }
      },
      {
        name: 'get_screener_quantitativo',
        description: 'Retorna as oportunidades da aba SCREENER_QUANTITATIVO.',
        inputSchema: { type: 'object', properties: {} }
      },
      {
        name: 'get_scanner_opcoes',
        description: 'Retorna a liquidez e gregas da aba SCANNER_OPCOES.',
        inputSchema: { type: 'object', properties: {} }
      },
      {
        name: 'get_maiores_lucros',
        description: 'Retorna dados da aba SELECAO_OPCOES_MAIORES_LUCROS.',
        inputSchema: { type: 'object', properties: {} }
      },
      {
        name: 'get_maiores_volumes',
        description: 'Retorna dados da aba SELECAO_MAIORES_VOLUMES.',
        inputSchema: { type: 'object', properties: {} }
      },
      {
        name: 'get_tendencia_m9m21',
        description: 'Retorna a tendência da aba RANKING_TENDENCIA_M9M21.',
        inputSchema: { type: 'object', properties: {} }
      },
      {
        name: 'get_correl_ibov',
        description: 'Retorna dados da aba RANKING_CORREL_IBOV.',
        inputSchema: { type: 'object', properties: {} }
      },
      {
        name: 'acionar_automacao_planilha',
        description: 'Dispara uma automação no Google Apps Script da planilha OPLab (atualização de dados, scanner, gregas etc). O servidor faz POST para o Web App configurado em APPS_SCRIPT_WEB_APP_URL com o token compartilhado e o nome da função. Retorna a resposta do Apps Script.',
        inputSchema: {
          type: 'object',
          properties: {
            nome_da_funcao: {
              type: 'string',
              description: 'Nome exato da função do Apps Script a executar.',
              enum: [
                'executarFluxoSequencial',
                'executarSequenciaScanner',
                'AtualizarNecton_Menu',
                'AtualizarDadosAtivos_Menu',
                'AtualizarDetalhes_Menu',
                'AtualizarGregasAPI_Menu',
                'CalcularGregasNativo_Menu',
                'AtualizarScannerOpcoes_Menu',
                'SyncBestCoveredOptionsRates_Menu',
                'SyncHighestOptionsVolume_Menu',
                'SyncM9M21Ranking_Menu',
                'SyncCorrelIbovRanking_Menu',
                'ScreenerQuantitativo_Menu'
              ]
            }
          },
          required: ['nome_da_funcao']
        }
      }
    ]
  };
});

mcpServer.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args = {} } = request.params;

  if (name === 'acionar_automacao_planilha') {
    try {
      const a = args as any;
      const funcao = typeof a.nome_da_funcao === 'string' ? a.nome_da_funcao.trim() : '';
      if (funcao === '') throw new Error('Parâmetro "nome_da_funcao" é obrigatório.');

      const url = process.env.APPS_SCRIPT_WEB_APP_URL;
      const token = process.env.APPS_SCRIPT_TOKEN;
      if (!url)   throw new Error('Variável APPS_SCRIPT_WEB_APP_URL não configurada.');
      if (!token) throw new Error('Variável APPS_SCRIPT_TOKEN não configurada.');

      const resp = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token, funcao }),
        redirect: 'follow',
      });
      const bodyText = await resp.text();
      let parsed: any = null;
      try { parsed = JSON.parse(bodyText); } catch { /* texto puro */ }

      if (!resp.ok) {
        return {
          content: [{ type: 'text', text: `Apps Script retornou HTTP ${resp.status}: ${bodyText}` }],
          isError: true,
        };
      }
      if (parsed && parsed.status === 'Erro') {
        return {
          content: [{ type: 'text', text: `Apps Script reportou erro: ${parsed.message || bodyText}` }],
          isError: true,
        };
      }
      return {
        content: [{ type: 'text', text: JSON.stringify(parsed ?? { raw: bodyText }, null, 2) }],
      };
    } catch (error: any) {
      return {
        content: [{ type: 'text', text: `Erro ao acionar automação: ${error.message}` }],
        isError: true,
      };
    }
  }

  if (!SPREADSHEET_ID) throw new Error('Variável SPREADSHEET_ID não configurada.');

  try {
    let range = '';
    if (name === 'get_cockpit_ativas') range = 'COCKPIT!A10:Z500';
    else if (name === 'get_cockpit_historico') range = 'COCKPIT!A10:Z500';
    else if (name === 'get_resumo_mensal') range = 'COCKPIT!A10:Z500';
    else if (name === 'get_cockpit_por_ativo') range = 'COCKPIT!A10:Z500';
    else if (name === 'get_resumo_por_ativo') range = 'COCKPIT!A10:Z500';
    else if (name === 'get_dashboard_mensal') range = 'COCKPIT!A10:Z500';
    else if (name === 'get_alertas_posicoes') range = 'COCKPIT!A10:Z500';
    else if (name === 'get_screener_quantitativo') range = 'SCREENER_QUANTITATIVO!A1:Z200';
    else if (name === 'get_scanner_opcoes') range = 'SCANNER_OPCOES!A1:Z500';
    else if (name === 'get_maiores_lucros') range = 'SELECAO_OPCOES_MAIORES_LUCROS!A1:Z200';
    else if (name === 'get_maiores_volumes') range = 'SELECAO_MAIORES_VOLUMES!A1:Z200';
    else if (name === 'get_tendencia_m9m21') range = 'RANKING_TENDENCIA_M9M21!A1:Z300';
    else if (name === 'get_correl_ibov') range = 'RANKING_CORREL_IBOV!A1:Z300';
    else throw new Error(`Ferramenta desconhecida: ${name}`);

    const response = await sheets.spreadsheets.values.get({ spreadsheetId: SPREADSHEET_ID, range });
    const rows = response.data.values || [];
    if (rows.length === 0) return { content: [{ type: 'text', text: 'Nenhum dado encontrado.' }] };

    const headers = rows[0];
    let data = rows.slice(1).map(row => {
      const obj: any = {};
      headers.forEach((header: string, i: number) => { obj[header] = row[i] || ''; });
      return obj;
    });

    // STATUS header da aba COCKPIT (contém "STATUS" mas não "STATUS_OP").
    const statusHeader = headers.find((h: string) => {
      const u = String(h).toUpperCase();
      return u.includes('STATUS') && !u.includes('STATUS_OP');
    });

    if (name === 'get_cockpit_ativas') {
      data = data.filter(item => {
        const status = String(item['STATUS'] || item['STATUS_OP'] || item['VENDA/COMPRA'] || '').toUpperCase();
        return status.includes('ATIVO') || (item['QTDE'] && item['QTDE'] !== '' && !status.includes('ENCERRADO'));
      });
    } else if (name === 'get_cockpit_historico') {
      data = data.filter(item => {
        const status = String(statusHeader ? item[statusHeader] : '').trim().toUpperCase();
        return status === 'ENCERRADO' || status === 'EXERCIDA';
      });
      const a = args as any;
      const argMonth = typeof a.trade_month === 'string' ? String(a.trade_month).trim() : '';
      const argTicker = typeof a.ticker === 'string' ? String(a.ticker).trim().toUpperCase() : '';
      if (argMonth !== '') data = data.filter(item => String(item['TRADE_MONTH'] || '').includes(argMonth));
      if (argTicker !== '') data = data.filter(item => String(item['TICKER'] || '').trim().toUpperCase() === argTicker);
    } else if (name === 'get_cockpit_por_ativo') {
      const a = args as any;
      const argTicker = typeof a.ticker === 'string' ? String(a.ticker).trim().toUpperCase() : '';
      if (argTicker === '') throw new Error('Parâmetro "ticker" é obrigatório.');
      data = data.filter(item => String(item['TICKER'] || '').trim().toUpperCase() === argTicker);
    } else if (name === 'get_resumo_mensal') {
      type Bucket = {
        trade_month: string;
        max_gain_venda: number;
        max_gain_compra: number;
        pl_realizado: number;
        qtde_encerradas: number;
        qtde_ativas: number;
      };
      const buckets = new Map<string, Bucket>();
      const getBucket = (m: string): Bucket => {
        let b = buckets.get(m);
        if (!b) {
          b = { trade_month: m, max_gain_venda: 0, max_gain_compra: 0, pl_realizado: 0, qtde_encerradas: 0, qtde_ativas: 0 };
          buckets.set(m, b);
        }
        return b;
      };
      for (const item of data) {
        const month = String(item['TRADE_MONTH'] || '').trim();
        if (month === '') continue;
        const status = String(statusHeader ? item[statusHeader] : '').trim().toUpperCase();
        // Só linhas com status reconhecido entram nos agregados
        if (status !== 'ENCERRADO' && status !== 'EXERCIDA' && status !== 'ATIVO') continue;

        const side = String(item['SIDE'] || '').trim().toUpperCase();
        const mg = parseNumberBR(item['MAX_GAIN']);
        const b = getBucket(month);

        // Prêmios somam TODAS as operações do mês (ativas + encerradas + exercidas) —
        // reflete a exposição total contratada no período. Mesma semântica do
        // get_dashboard_mensal e get_resumo_por_ativo.
        if (side === 'VENDA')  b.max_gain_venda  += mg;
        if (side === 'COMPRA') b.max_gain_compra += mg;

        // P&L realizado e count de encerradas: apenas encerradas/exercidas
        if (status === 'ENCERRADO' || status === 'EXERCIDA') {
          b.pl_realizado += parseNumberBR(item['PL_VALUE']);
          b.qtde_encerradas += 1;
        } else if (status === 'ATIVO') {
          b.qtde_ativas += 1;
        }
      }
      const round2 = (n: number) => Math.round(n * 100) / 100;
      data = Array.from(buckets.values())
        .sort((a, b) => a.trade_month.localeCompare(b.trade_month))
        .map((b) => ({
          trade_month: b.trade_month,
          max_gain_venda: round2(b.max_gain_venda),
          max_gain_compra: round2(b.max_gain_compra),
          premio_liquido: round2(b.max_gain_venda + b.max_gain_compra),
          pl_realizado: round2(b.pl_realizado),
          qtde_encerradas: b.qtde_encerradas,
          qtde_ativas: b.qtde_ativas,
        }));
    } else if (name === 'get_resumo_por_ativo') {
      const a = args as any;
      const ticker = typeof a.ticker === 'string' ? String(a.ticker).trim().toUpperCase() : '';
      if (ticker === '') throw new Error('Parâmetro "ticker" é obrigatório.');

      const filtered = data.filter(item => String(item['TICKER'] || '').trim().toUpperCase() === ticker);

      const statusOf = (item: any) => String(statusHeader ? item[statusHeader] : '').trim().toUpperCase();
      const encerradas = filtered.filter(item => statusOf(item) === 'ENCERRADO');
      const ativasArr = filtered.filter(item => statusOf(item) === 'ATIVO');
      const exercidas = filtered.filter(item => statusOf(item) === 'EXERCIDA');
      const realizadas = encerradas.concat(exercidas);

      const sideOf = (item: any) => String(item['SIDE'] || '').trim().toUpperCase();
      // Prêmios somam TODAS as operações do ticker (ativas + encerradas + exercidas),
      // não só as realizadas — refletem a exposição total já contratada.
      const premio_bruto_vendas = filtered
        .filter(item => sideOf(item) === 'VENDA')
        .reduce((sum, item) => sum + parseNumberBR(item['MAX_GAIN']), 0);
      const custo_protecoes = filtered
        .filter(item => sideOf(item) === 'COMPRA')
        .reduce((sum, item) => sum + parseNumberBR(item['MAX_GAIN']), 0);
      const premio_liquido_total = premio_bruto_vendas + custo_protecoes;
      // P&L realizado segue só nas encerradas/exercidas
      const pl_realizado_total = realizadas.reduce((sum, item) => sum + parseNumberBR(item['PL_VALUE']), 0);
      const pl_ativo_mtm = ativasArr.reduce((sum, item) => sum + parseNumberBR(item['PL_VALUE']), 0);

      const pls_enc = encerradas.map(item => parseNumberBR(item['PL_VALUE']));
      const wins = pls_enc.filter(v => v > 0).length;
      const win_rate_pct = encerradas.length > 0 ? (wins / encerradas.length) * 100 : 0;
      const maior_ganho = pls_enc.length > 0 ? Math.max(...pls_enc) : 0;
      const maior_perda = pls_enc.length > 0 ? Math.min(...pls_enc) : 0;

      // Posições ativas: mesma lógica de get_cockpit_ativas, restrita a este ticker
      const posicoes_ativas = filtered.filter(item => {
        const s = String(item['STATUS'] || item['STATUS_OP'] || item['VENDA/COMPRA'] || '').toUpperCase();
        return s.includes('ATIVO') || (item['QTDE'] && item['QTDE'] !== '' && !s.includes('ENCERRADO'));
      });

      const round2 = (n: number) => Math.round(n * 100) / 100;
      data = {
        ticker,
        resumo_historico: {
          total_operacoes: filtered.length,
          encerradas: encerradas.length,
          ativas: ativasArr.length,
          exercidas: exercidas.length,
          premio_bruto_vendas: round2(premio_bruto_vendas),
          custo_protecoes: round2(custo_protecoes),
          premio_liquido_total: round2(premio_liquido_total),
          pl_realizado: round2(pl_realizado_total),
          pl_ativo_mtm: round2(pl_ativo_mtm),
          win_rate_pct: round2(win_rate_pct),
          maior_ganho: round2(maior_ganho),
          maior_perda: round2(maior_perda),
        },
        posicoes_ativas,
      } as any;
    } else if (name === 'get_dashboard_mensal') {
      const a = args as any;
      const mes = typeof a.mes === 'string' ? String(a.mes).trim() : '';
      if (mes === '') throw new Error('Parâmetro "mes" é obrigatório.');
      const ano = typeof a.ano === 'string' && a.ano.trim() !== ''
        ? String(a.ano).trim()
        : String(new Date().getFullYear());

      const mesNum = parseInt(mes, 10);
      const anoNum = parseInt(ano, 10);
      const periodoStr = `${String(mesNum).padStart(2, '0')}/${anoNum}`;

      // Mês anterior (rola para dezembro do ano anterior se aplicável)
      let mesAnt = mesNum - 1;
      let anoAnt = anoNum;
      if (mesAnt < 1) { mesAnt = 12; anoAnt -= 1; }
      const periodoAntStr = `${String(mesAnt).padStart(2, '0')}/${anoAnt}`;

      const statusOf = (item: any) => String(statusHeader ? item[statusHeader] : '').trim().toUpperCase();
      const sideOf = (item: any) => String(item['SIDE'] || '').trim().toUpperCase();

      // Match flexível de TRADE_MONTH: aceita "5", "05", "5/2026", "05/2026",
      // "2026-05", "2026-5", "2026/05", "2026/5".
      const matchMonth = (tmRaw: string, m: number, y: number): boolean => {
        const tm = String(tmRaw || '').trim();
        if (tm === '') return false;
        const mStr = String(m);
        const mPad = mStr.padStart(2, '0');
        const yStr = String(y);
        return (
          tm === mStr || tm === mPad ||
          tm === `${mPad}/${yStr}` || tm === `${mStr}/${yStr}` ||
          tm === `${yStr}-${mPad}` || tm === `${yStr}-${mStr}` ||
          tm === `${yStr}/${mPad}` || tm === `${yStr}/${mStr}`
        );
      };

      // Itera UMA vez por todo o data, agregando os dois meses (corrente + anterior)
      // e também as linhas do mês corrente para os campos derivados (melhor/pior, por_ativo).
      interface Bucket {
        max_gain_venda: number;
        max_gain_compra: number;
        pl_realizado: number;
        qtde_encerradas: number;
        qtde_ativas: number;
      }
      const novoBucket = (): Bucket => ({ max_gain_venda: 0, max_gain_compra: 0, pl_realizado: 0, qtde_encerradas: 0, qtde_ativas: 0 });
      const cur = novoBucket();
      const ant = novoBucket();
      const linhasMes: any[] = [];

      for (const item of data) {
        const tm = String(item['TRADE_MONTH'] || '').trim();
        if (tm === '') continue;
        const isCur = matchMonth(tm, mesNum, anoNum);
        const isAnt = matchMonth(tm, mesAnt, anoAnt);
        if (!isCur && !isAnt) continue;

        const status = statusOf(item);
        // Só considera linhas com status reconhecido para evitar lixo
        if (status !== 'ENCERRADO' && status !== 'EXERCIDA' && status !== 'ATIVO') {
          if (isCur) linhasMes.push(item);
          continue;
        }

        const side = sideOf(item);
        const mg = parseNumberBR(item['MAX_GAIN']);
        const targets: Bucket[] = [];
        if (isCur) targets.push(cur);
        if (isAnt) targets.push(ant);

        // Prêmios somam TODAS as operações do mês (ativas + encerradas + exercidas) —
        // refletem a exposição total já contratada no período.
        for (const b of targets) {
          if (side === 'VENDA') b.max_gain_venda += mg;
          if (side === 'COMPRA') b.max_gain_compra += mg;
        }

        if (status === 'ENCERRADO' || status === 'EXERCIDA') {
          const pl = parseNumberBR(item['PL_VALUE']);
          for (const b of targets) {
            b.pl_realizado += pl;
            b.qtde_encerradas += 1;
          }
        } else if (status === 'ATIVO') {
          for (const b of targets) b.qtde_ativas += 1;
        }

        if (isCur) linhasMes.push(item);
      }

      const premio_bruto_vendas = cur.max_gain_venda;
      const custo_protecoes     = cur.max_gain_compra;
      const premio_liquido      = premio_bruto_vendas + custo_protecoes;
      const pl_realizado        = cur.pl_realizado;

      // Estatísticas das encerradas do mês corrente (a partir das linhasMes)
      const encerradasMes = linhasMes.filter(item => {
        const s = statusOf(item);
        return s === 'ENCERRADO' || s === 'EXERCIDA';
      });
      const pls = encerradasMes.map(item => parseNumberBR(item['PL_VALUE']));
      const wins = pls.filter(v => v > 0).length;
      const win_rate_encerradas_pct = encerradasMes.length > 0 ? (wins / encerradasMes.length) * 100 : 0;
      const maior_ganho_mes = pls.length > 0 ? Math.max(...pls) : 0;
      const maior_perda_mes = pls.length > 0 ? Math.min(...pls) : 0;

      let melhor_operacao = '';
      let pior_operacao = '';
      if (encerradasMes.length > 0) {
        let melhorPL = -Infinity, piorPL = Infinity;
        for (const item of encerradasMes) {
          const pl = parseNumberBR(item['PL_VALUE']);
          const ot = String(item['OPTION_TICKER'] || item['TICKER'] || '').trim();
          if (pl > melhorPL) { melhorPL = pl; melhor_operacao = ot; }
          if (pl < piorPL)  { piorPL = pl;  pior_operacao  = ot; }
        }
      }

      const premio_liquido_anterior = ant.max_gain_venda + ant.max_gain_compra;
      const variacao_pct = premio_liquido_anterior !== 0
        ? ((premio_liquido - premio_liquido_anterior) / Math.abs(premio_liquido_anterior)) * 100
        : 0;

      // Agrupamento por ticker dentro do mês — mesmo padrão (separa VENDA/COMPRA)
      type PorAtivo = {
        ticker: string;
        operacoes: number;
        max_gain_venda: number;
        max_gain_compra: number;
        pl_realizado: number;
      };
      const porAtivoMap = new Map<string, PorAtivo>();
      for (const item of linhasMes) {
        const t = String(item['TICKER'] || '').trim().toUpperCase();
        if (t === '') continue;
        const s = statusOf(item);
        if (s !== 'ENCERRADO' && s !== 'EXERCIDA' && s !== 'ATIVO') continue;

        let pa = porAtivoMap.get(t);
        if (!pa) {
          pa = { ticker: t, operacoes: 0, max_gain_venda: 0, max_gain_compra: 0, pl_realizado: 0 };
          porAtivoMap.set(t, pa);
        }
        pa.operacoes += 1;

        // Prêmios somam TODAS as posições do mês (mesma semântica do total acima)
        const side = sideOf(item);
        const mg = parseNumberBR(item['MAX_GAIN']);
        if (side === 'VENDA')  pa.max_gain_venda  += mg;
        if (side === 'COMPRA') pa.max_gain_compra += mg;

        // P&L realizado segue só nas realizadas
        if (s === 'ENCERRADO' || s === 'EXERCIDA') {
          pa.pl_realizado += parseNumberBR(item['PL_VALUE']);
        }
      }

      const encerradas = encerradasMes; // alias para consistência abaixo
      const ativasArr = linhasMes.filter(item => statusOf(item) === 'ATIVO');

      const round2 = (n: number) => Math.round(n * 100) / 100;
      data = {
        periodo: periodoStr,
        performance: {
          premio_bruto_vendas: round2(premio_bruto_vendas),
          custo_protecoes: round2(custo_protecoes),
          premio_liquido: round2(premio_liquido),
          pl_realizado: round2(pl_realizado),
          qtde_encerradas: encerradas.length,
          qtde_ativas: ativasArr.length,
          win_rate_encerradas_pct: round2(win_rate_encerradas_pct),
          maior_ganho_mes: round2(maior_ganho_mes),
          maior_perda_mes: round2(maior_perda_mes),
          melhor_operacao,
          pior_operacao,
        },
        comparativo_mes_anterior: {
          mes_anterior: periodoAntStr,
          premio_liquido_anterior: round2(premio_liquido_anterior),
          variacao_pct: round2(variacao_pct),
        },
        por_ativo: Array.from(porAtivoMap.values()).map(p => ({
          ticker: p.ticker,
          operacoes: p.operacoes,
          premio_liquido: round2(p.max_gain_venda + p.max_gain_compra),
          pl_realizado: round2(p.pl_realizado),
        })),
      } as any;
    } else if (name === 'get_alertas_posicoes') {
      // Posições ATIVAS via mesma lógica de get_cockpit_ativas
      const ativasArr = data.filter(item => {
        const s = String(item['STATUS'] || item['STATUS_OP'] || item['VENDA/COMPRA'] || '').toUpperCase();
        return s.includes('ATIVO') || (item['QTDE'] && item['QTDE'] !== '' && !s.includes('ENCERRADO'));
      });

      // DTE: dias entre EXPIRY e hoje. Aceita YYYY-MM-DD ou DD/MM/YYYY.
      const hoje = new Date();
      hoje.setHours(0, 0, 0, 0);
      const parseDate = (raw: string): Date | null => {
        if (!raw) return null;
        const s = String(raw).trim();
        let m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
        if (m) return new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10));
        m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/);
        if (m) return new Date(parseInt(m[3], 10), parseInt(m[2], 10) - 1, parseInt(m[1], 10));
        return null;
      };

      interface Alerta {
        nivel: 'CRITICO' | 'ALERTA' | 'AVISO';
        motivo: string;
        descricao: string;
        opcao: string;
        ticker: string;
        side: string;
        dte: number;
        strike: number;
        spot: number;
        moneyness: string;
        pl_value: number;
        acao_sugerida: string;
      }
      const criticos: Alerta[] = [];
      const alertas: Alerta[] = [];
      const avisos:   Alerta[] = [];
      let saudaveis = 0;

      for (const item of ativasArr) {
        const side = String(item['SIDE'] || '').trim().toUpperCase();
        // Regras se aplicam apenas a SIDE = VENDA
        if (side !== 'VENDA') { saudaveis += 1; continue; }

        const opcao  = String(item['OPTION_TICKER'] || item['TICKER'] || '').trim();
        const ticker = String(item['TICKER'] || '').trim();
        const expiry = parseDate(String(item['EXPIRY'] || ''));
        const dte = expiry ? Math.ceil((expiry.getTime() - hoje.getTime()) / 86400000) : -1;
        const strike = parseNumberBR(item['STRIKE']);
        const spot   = parseNumberBR(item['SPOT']);
        const moneyness = String(item['MONEYNESS'] || '').trim().toUpperCase();
        const plValue = parseNumberBR(item['PL_VALUE']);
        const maxGain = parseNumberBR(item['MAX_GAIN']);

        const base = { opcao, ticker, side, dte, strike, spot, moneyness, pl_value: plValue };

        // CRITICO
        if (dte > 0 && dte < 10) {
          criticos.push({ ...base, nivel: 'CRITICO', motivo: 'DTE_CRITICO',
            descricao: `${opcao} vence em ${dte} dias`, acao_sugerida: 'Encerrar urgente' });
          continue;
        }
        if (moneyness === 'ITM' && dte > 0 && dte < 20) {
          criticos.push({ ...base, nivel: 'CRITICO', motivo: 'ITM_DTE_CRITICO',
            descricao: `${opcao} ITM com ${dte} dias`, acao_sugerida: 'Avaliar encerramento' });
          continue;
        }
        if (plValue < 0 && maxGain > 0 && Math.abs(plValue) > maxGain) {
          criticos.push({ ...base, nivel: 'CRITICO', motivo: 'STOP_ATINGIDO',
            descricao: `${opcao} com perda > 100% do prêmio máximo`, acao_sugerida: 'Stop atingido — encerrar' });
          continue;
        }

        // ALERTA
        if (moneyness === 'ITM') {
          alertas.push({ ...base, nivel: 'ALERTA', motivo: 'ITM',
            descricao: `${opcao} está ITM`, acao_sugerida: 'Monitorar diariamente' });
          continue;
        }
        if (dte >= 10 && dte <= 21) {
          alertas.push({ ...base, nivel: 'ALERTA', motivo: 'DTE_MEDIO',
            descricao: `${opcao} vence em ${dte} dias`, acao_sugerida: 'Planejar manejo' });
          continue;
        }
        if (plValue < 0 && maxGain > 0 && Math.abs(plValue) > maxGain * 0.5 && Math.abs(plValue) <= maxGain) {
          alertas.push({ ...base, nivel: 'ALERTA', motivo: 'PL_NEGATIVO_50_100',
            descricao: `${opcao} perda entre 50% e 100% do prêmio máximo`, acao_sugerida: 'Planejar manejo' });
          continue;
        }

        // AVISO
        if (dte >= 22 && dte <= 30) {
          avisos.push({ ...base, nivel: 'AVISO', motivo: 'DTE_MODERADO',
            descricao: `${opcao} vence em ${dte} dias`, acao_sugerida: 'Acompanhar' });
          continue;
        }
        if (moneyness === 'ATM') {
          avisos.push({ ...base, nivel: 'AVISO', motivo: 'ATM',
            descricao: `${opcao} está ATM`, acao_sugerida: 'Acompanhar' });
          continue;
        }

        saudaveis += 1;
      }

      data = {
        total_alertas: criticos.length + alertas.length + avisos.length,
        criticos,
        alertas,
        avisos,
        saudaveis,
      } as any;
    }
    return { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] };
  } catch (error: any) {
    return { content: [{ type: 'text', text: `Erro: ${error.message}` }], isError: true };
  }
});

app.listen(PORT, () => console.log(`[Sheets-MCP] Ativado na porta ${PORT}`));

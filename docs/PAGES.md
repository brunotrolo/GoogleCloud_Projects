# Publicar o painel no GitHub Pages

O painel é a página `docs/index.html`. Ele lê `docs/data/costs.json` e mostra
o total, o custo por serviço, **a origem de cada centavo (por SKU)**, por dia e
por projeto.

## Ligar o GitHub Pages (uma vez, ~1 min)

1. No repositório → **Settings** → **Pages**.
2. Em **Build and deployment** → **Source**: escolha **Deploy from a branch**.
3. Em **Branch**: escolha a branch (ex.: `main`) e a pasta **`/docs`**. Clique **Save**.
4. Aguarde ~1 min. O endereço aparece no topo da própria página de Pages, algo como:

   ```
   https://brunotrolo.github.io/GoogleCloud_Projects/
   ```

Pronto. Esse link é o seu painel. 📊

## De onde vêm os dados

- **Agora**: `docs/data/costs.json` está semeado com os dados reais da fatura de
  junho/2026, só para você ver o painel funcionando de imediato.
- **Automático**: quando o BigQuery Billing Export estiver ligado (ver
  [`SETUP.md`](SETUP.md)), o GitHub Actions roda todo dia, regenera o
  `costs.json` com os números atualizados e o painel reflete sozinho.

> O painel é só leitura e mostra apenas valores agregados de custo — não expõe
> credenciais nem dados sensíveis.

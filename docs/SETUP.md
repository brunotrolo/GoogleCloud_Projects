# Setup — Monitoria Total de Custos GCP

Você só precisa fazer isto **uma vez**. Depois o relatório se gera sozinho todo dia
e é commitado em `reports/`.

São 3 etapas: (1) ligar o billing export, (2) dar acesso ao GitHub, (3) configurar os secrets.

---

## Etapa 1 — Ligar o BigQuery Billing Export (detalhado)

Essa é a fonte que registra **cada SKU em cada recurso**. Sem ela, não dá pra saber
"a origem de cada centavo".

1. Console GCP → **Billing** → **Billing export** → aba **BigQuery export**.
2. Em **Detailed usage cost**, clique em **Edit settings**.
3. Escolha (ou crie) um projeto e um dataset BigQuery (ex.: dataset `billing`).
4. Salve.

> ⚠️ O export só começa a popular dados **a partir de agora** — ele não é retroativo.
> Deixe ligado uns dias para acumular histórico. O custo do próprio export é centavos.

Depois de criado, a tabela terá um nome assim:

```
SEU_PROJETO.billing.gcp_billing_export_resource_v1_XXXXXX_XXXXXX_XXXXXX
```

Guarde esse nome completo — é o `BQ_BILLING_TABLE`.

---

## Etapa 2 — Criar a Service Account de leitura

No **Cloud Shell** (Console GCP → ícone do terminal), rode (troque `SEU_PROJETO`):

```bash
PROJ=SEU_PROJETO
gcloud config set project $PROJ

# cria a service account
gcloud iam service-accounts create cost-report \
  --display-name="Cost Report (somente leitura billing)"

SA="cost-report@${PROJ}.iam.gserviceaccount.com"

# permissões mínimas: rodar query e ler os dados do BigQuery
gcloud projects add-iam-policy-binding $PROJ \
  --member="serviceAccount:${SA}" --role="roles/bigquery.jobUser"
gcloud projects add-iam-policy-binding $PROJ \
  --member="serviceAccount:${SA}" --role="roles/bigquery.dataViewer"
```

### Autenticação — escolha UM caminho

**Caminho B (mais simples — chave JSON):**

```bash
gcloud iam service-accounts keys create chave.json --iam-account=$SA
cat chave.json   # copie todo o conteúdo
```

> Apague o `chave.json` local depois de colar no GitHub. (`rm chave.json`)

**Caminho A (recomendado — Workload Identity Federation, sem chave):**
mais seguro, porém com mais passos. Veja
<https://github.com/google-github-actions/auth#setting-up-workload-identity-federation>.
Ao final você terá um `GCP_WIF_PROVIDER` e o e-mail da SA (`GCP_SERVICE_ACCOUNT`).

---

## Etapa 3 — Configurar os Secrets no GitHub

No repositório → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**:

| Secret | Valor |
|--------|-------|
| `BQ_BILLING_TABLE` | nome completo da tabela do export (Etapa 1) |
| `GCP_SA_KEY` | conteúdo do `chave.json` (se usou o Caminho B) |
| `GCP_WIF_PROVIDER` | provider WIF (se usou o Caminho A) |
| `GCP_SERVICE_ACCOUNT` | e-mail da SA (se usou o Caminho A) |

---

## Pronto. E agora?

- O Action roda **todo dia às 06:00 BRT** e commita `reports/cost-report-AAAA-MM-DD.md`.
- Para rodar **na hora**: aba **Actions** → **Relatório de Custos GCP** → **Run workflow**.
- Quer testar local? No Cloud Shell:

  ```bash
  export BQ_BILLING_TABLE="SEU_PROJETO.billing.gcp_billing_export_resource_v1_XXXXXX"
  export DIAS=30
  ./scripts/gerar_relatorio.sh
  ```

Depois é só me chamar: **"lê o último relatório de custos"** que eu analiso e te digo
de onde vem cada centavo. 👇 (veja `docs/COMO_LER.md`)

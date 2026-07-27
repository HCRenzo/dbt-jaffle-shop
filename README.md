# jaffle_shop — dbt + DuckDB

Proyecto de portfolio: un pipeline analítico completo con dbt, corriendo
100% local sobre [DuckDB](https://duckdb.org/) — sin infraestructura, sin
credenciales, reproducible con un `git clone`.

## Arquitectura

Capas equivalentes a medallion, con nomenclatura estándar de dbt:

| Capa | Carpeta | Rol |
|---|---|---|
| Bronze | `seeds/` | Datos crudos (CSV), cargados 1:1 sin transformar |
| Silver (staging) | `models/staging/` | Renombrado/tipado, un modelo por seed, sin joins |
| Silver (intermediate) | `models/intermediate/` | Joins y agregaciones reutilizables |
| Gold (marts) | `models/marts/` | `fct_orders` (incremental) y `dim_customers`, listos para consumo |

Además: snapshot SCD2 sobre `orders` (`snapshots/`), contratos de modelo
enforced en los marts, y un exposure documentando un dashboard downstream.

## Cómo correr el proyecto localmente

```bash
uv venv --python 3.11 .venv
source .venv/bin/activate
uv pip install -r requirements.txt
dbt deps

dbt build --profiles-dir .
```

Esto crea `jaffle_shop.duckdb` en la raíz del proyecto (no se versiona,
se reconstruye completo desde seeds + models).

### Explorar los datos

```bash
duckdb jaffle_shop.duckdb -readonly
```

### Ver la documentación y el linaje

```bash
dbt docs generate --profiles-dir .
dbt docs serve --profiles-dir .
```

## Calidad

```bash
sqlfluff lint models/ tests/ snapshots/
```

## CI

`.github/workflows/ci.yml` corre en cada PR y en cada push a `main`:
- **Lint**: sqlfluff sobre todo el SQL del proyecto.
- **Build + test (Slim CI)**: en PRs, solo construye lo que cambió (y lo
  que depende de eso), comparando contra el último build exitoso de
  `main` — no reconstruye el proyecto entero en cada PR.

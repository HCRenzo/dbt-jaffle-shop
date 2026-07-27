# jaffle_shop — dbt + DuckDB

![CI](https://github.com/HCRenzo/dbt-jaffle-shop/actions/workflows/ci.yml/badge.svg)

Proyecto de portfolio: un pipeline analítico completo construido con **dbt**,
corriendo 100% local sobre **[DuckDB](https://duckdb.org/)** — sin
infraestructura, sin credenciales, reproducible con un `git clone`.

Usa el dataset clásico de `jaffle_shop` (clientes, órdenes, pagos) como base
de datos de ejemplo, pero el objetivo del repo no es el dataset — es mostrar
un conjunto de prácticas de ingeniería analítica que sí importan en un
proyecto dbt real: arquitectura por capas, tests en cada nivel, snapshots,
modelos incrementales, contratos de esquema, exposures, lint, y CI con
Slim CI + auditoría de estructura.

## Por qué existe este repo

No es un tutorial de "hola mundo" de dbt. Cada práctica de acá resuelve un
problema concreto que aparece en proyectos dbt reales cuando crecen:

| Problema real | Cómo se resuelve acá |
|---|---|
| El SQL de transformación mezcla limpieza con lógica de negocio | Capas separadas: staging (limpieza) → intermediate (joins/agregaciones) → marts (consumo) |
| Nadie sabe si un dato está bien hasta que un dashboard se rompe | Tests genéricos + singulares en cada capa, tests en CI en cada PR |
| Se pierde el historial de cómo cambió un dato en el tiempo | Snapshot SCD tipo 2 sobre `orders` |
| Reconstruir todo el warehouse en cada corrida no escala | `fct_orders` incremental (`merge`), Slim CI en el pipeline |
| Un cambio de tipo de columna rompe un dashboard sin avisar | Contratos de modelo (`contract: enforced`) en los marts |
| Nadie sabe qué consume realmente un modelo, ni el impacto de tocarlo | Exposure documentando un dashboard downstream |
| El estilo del SQL deriva con cada persona que escribe código | sqlfluff + CI |
| El proyecto se desordena con el tiempo (fan-out, modelos sin test, carpetas mal puestas) | dbt-project-evaluator auditando estructura en cada PR |
| Cada PR reconstruye el proyecto entero, CI lento y caro | Slim CI: solo se construye lo que cambió + lo que depende de eso |

## Arquitectura

Capas equivalentes a medallion, con nomenclatura estándar de dbt (no hay
"bronze/silver/gold" como palabra reservada — es organización por carpetas +
materialización):

| Capa medallion | Carpeta dbt | Rol | Materialización |
|---|---|---|---|
| Bronze | `seeds/` | Datos crudos (CSV), cargados 1:1 sin transformar. Sustituye a un `source` real por no tener pipeline de ingesta. | tabla |
| Silver (staging) | `models/staging/` | Un modelo por seed. Renombrado, tipado, normalización de unidad. Sin joins, sin lógica de negocio. | view |
| Silver (intermediate) | `models/intermediate/` | Joins y cambios de grano reutilizables por más de un mart. | view |
| Gold (marts) | `models/marts/` | `fct_orders` (hechos, incremental) y `dim_customers` (dimensión). Contrato enforced. Es la interfaz pública del proyecto. | table / incremental |

```
raw_customers (seed) ──→ stg_customers ──────────────────────┐
raw_orders (seed)    ──→ stg_orders    ──→ int_orders_        ├──→ dim_customers ──→ customer_retention_dashboard (exposure)
raw_payments (seed)  ──→ stg_payments  ──┘   payments_joined ─┴──→ fct_orders
                      └──→ orders_snapshot   (SCD2, rama independiente)
```

## Qué hay en cada carpeta

```
seeds/          raw_customers, raw_orders, raw_payments (bronze)
models/
  staging/      stg_customers, stg_orders, stg_payments
  intermediate/ int_orders_payments_joined
  marts/        fct_orders, dim_customers, exposures.yml
snapshots/      orders_snapshot.sql (SCD2 sobre order_status)
tests/          tests singulares (reglas de negocio que no cubre un test genérico)
macros/         cents_to_dollars.sql
.github/
  workflows/    ci.yml — lint, auditoría de estructura, build+test (Slim CI)
```

## Decisiones de diseño (y sus trade-offs)

- **Seeds en vez de sources**: no hay pipeline de ingesta real, así que los
  CSV simulan la capa bronze. En un proyecto real, `staging/` leería de
  `source()`, no de `ref()` a un seed.
- **`fct_orders` incremental con `merge`**: solo reconstruye lo nuevo
  (`order_date > max(order_date)` ya presente). Con 99 filas esto no importa
  para performance, pero sí importa el trade-off: `merge` nunca borra filas
  que desaparecen de la fuente (requiere `--full-refresh` para reconciliar
  borrados) y el filtro por fecha no detecta actualizaciones a órdenes
  viejas sin un `updated_at` confiable.
- **Contratos solo en los marts**: son la interfaz pública consumida por
  fuera de dbt. Un cambio de tipo ahí rompe el build antes de llegar a
  producción — verificado en vivo forzando un mismatch intencional durante
  la construcción del proyecto.
- **Slim CI adaptado a un warehouse basado en archivo**: Slim CI con
  `--defer` asume un warehouse persistente y compartido (Snowflake,
  BigQuery). DuckDB es un archivo que no persiste entre corridas de CI, así
  que en cada push a `main` se sube el `.duckdb` ya construido como
  artifact, y los PRs lo restauran antes de correr
  `--select state:modified+` — el equivalente de `--defer` para un
  warehouse de archivo único.
- **`access: public` en los marts**: dbt-project-evaluator señaló que el
  exposure dependía de modelos con acceso `protected` (el default). Se
  marcaron `fct_orders`/`dim_customers` como `public` porque son,
  literalmente, la interfaz pública que el exposure formaliza.

## Cómo correr el proyecto localmente

```bash
uv venv --python 3.11 .venv
source .venv/bin/activate
uv pip install -r requirements.txt
dbt deps

dbt build --profiles-dir .
```

Esto crea `jaffle_shop.duckdb` en la raíz (no se versiona — se reconstruye
completo desde seeds + models).

### Explorar los datos

```bash
duckdb jaffle_shop.duckdb -readonly
```

### Ver la documentación y el linaje

```bash
dbt docs generate --profiles-dir .
dbt docs serve --profiles-dir .
```

### Simular un cambio de estado (probar el snapshot)

```bash
dbt snapshot --profiles-dir .                    # línea base
# editar seeds/raw_orders.csv, cambiar un status
dbt seed --select raw_orders --profiles-dir .
dbt snapshot --profiles-dir .                     # dbt cierra la versión vieja, abre una nueva
```

## Testing

| Capa | Qué se testea | Por qué ahí |
|---|---|---|
| staging | `unique`/`not_null` en PKs, `accepted_values` en categóricos, `dbt_utils.accepted_range` | Detectar drift de la fuente lo antes posible |
| intermediate | `unique`/`not_null` en la clave post-join | Verificar que el join no duplicó filas (chequeo de grano, no de PK) |
| marts | `unique`/`not_null`, `relationships` (integridad referencial fact↔dim) | Es la garantía que un consumidor final asume |
| singular (`tests/`) | `order_total >= 0` | Regla de negocio que ningún test genérico expresa |

```bash
dbt build --profiles-dir .          # seeds + snapshots + models + tests, en orden de DAG
```

## Calidad de código

```bash
sqlfluff lint models/ tests/ snapshots/
```

## Auditoría de estructura del proyecto

```bash
dbt build --select package:dbt_project_evaluator --profiles-dir .
```

Audita fan-out excesivo, modelos sin tests, modelos sin documentar,
modelos en la carpeta que no corresponde a su prefijo, exposures
dependiendo de modelos no públicos, y más — sobre la estructura del
proyecto, no sobre los datos.

## CI

`.github/workflows/ci.yml` corre tres jobs en cada PR y en cada push a `main`:

1. **Lint** — sqlfluff sobre todo el SQL del proyecto.
2. **Project structure audit** — dbt-project-evaluator, independiente del build (solo necesita el manifest, corre incluso contra un warehouse vacío).
3. **Build + test (Slim CI)** — en PRs, descarga el último estado bueno de `main` (manifest + `.duckdb`) y construye solo `state:modified+`; en push a `main`, build completo y sube el nuevo estado base.

## Stack

dbt-core 1.12 · dbt-duckdb · DuckDB · dbt_utils · dbt-project-evaluator · sqlfluff · GitHub Actions

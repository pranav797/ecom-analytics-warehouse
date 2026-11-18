# Phase checks

After each phase, run the checks for that phase. Each one says what was built, how to confirm it,
what you should see, and the questions you should be able to answer before moving on.

All commands run from the repo root in Git Bash. To query DuckDB, use this pattern
(swap in any SQL):

```bash
.venv/Scripts/python -c "import duckdb; print(duckdb.connect('data/warehouse.duckdb', read_only=True).sql('SELECT 1'))"
```

---

## Phase 2: Staging layer

### What happened
- `warehouse/` is now a dbt project:
  - `dbt_project.yml` names the project and says each folder's models land in a schema with the
    folder's name (`staging`, `intermediate`, `marts`).
  - Staging and intermediate models are **views**: saved queries with no stored data. Marts are
    **tables**.
  - `profiles.yml` tells dbt which database to connect to: the same DuckDB file that
    `load_raw.py` writes, picked from `WAREHOUSE_PATH`.
  - `macros/generate_schema_name.sql` overrides dbt's default schema naming. Without it, the
    schema would be called `main_staging` instead of `staging`.
- `models/staging/_sources.yml` registers the 9 `raw.*` tables as **sources**. Models refer to
  them as `{{ source('raw', 'orders') }}` instead of hard-coding `raw.orders`, which lets dbt draw
  the lineage graph.
- There are 9 `stg_*.sql` models, one per raw table. Each one only renames columns, casts types
  (text to timestamp, date, decimal, integer) and fixes the source's misspelled
  `product_name_lenght` column. There are no joins and no filters.
- `models/staging/_staging.yml` documents the models and declares **30 tests**:
  - `unique` + `not_null` on every primary key.
  - Uniqueness on **composite keys** for the tables where no single column is unique. For
    example, an order item is identified by `order_id || '-' || order_item_id`.
  - `accepted_values` on `order_status`, `payment_type` and `review_score` (1–5).

### Run it
```bash
cd warehouse && ../.venv/Scripts/dbt build; cd ..
```
You should see `PASS=39 WARN=0 ERROR=0` (9 views + 30 tests). dbt also prints one warning:
*"Configuration paths exist ... which do not apply to any resources"*. It appears because the
`intermediate/` and `marts/` folders are still empty, and it goes away in Phase 3.

### Confirm the output
1. **The staging schema exists and contains 9 views**:
   ```bash
   .venv/Scripts/python -c "import duckdb; print(duckdb.connect('data/warehouse.duckdb', read_only=True).sql(\"SELECT table_schema, table_name, table_type FROM information_schema.tables WHERE table_schema='staging'\"))"
   ```
2. **Types changed**. In raw everything is VARCHAR; in staging, dates and numbers are real types:
   ```bash
   .venv/Scripts/python -c "import duckdb; print(duckdb.connect('data/warehouse.duckdb', read_only=True).sql('DESCRIBE staging.stg_orders'))"
   ```
   `purchased_at` should be TIMESTAMP and `estimated_delivery_date` should be DATE.
3. **Look at the SQL dbt actually ran**. Open `warehouse/target/compiled/olist_warehouse/models/staging/stg_orders.sql`.
   The `{{ source(...) }}` reference has been replaced with a real table name.
4. **Look at what a test is**. Open any file under `warehouse/target/compiled/olist_warehouse/models/staging/_staging.yml/`.
   Each test is just a query that returns the rows that break the rule. A test passes when that
   query returns 0 rows.
5. **Watch a test fail on purpose**. In `_staging.yml`, delete `approved` from the
   `order_status` values and run `../.venv/Scripts/dbt test --select stg_orders`. It should fail
   with 1 result: the 2 orders with status `approved` are counted together. Then put `approved` back.
6. **Look at the lineage graph**:
   ```bash
   cd warehouse && ../.venv/Scripts/dbt docs generate && ../.venv/Scripts/dbt docs serve; cd ..
   ```
   Click the graph icon at the bottom right. Each source has an arrow to its staging model. Press
   Ctrl+C to stop the server.

### Things the data taught us (worth remembering)
| Finding | Why it matters later |
|---|---|
| `review_id` is **not** unique (98,410 ids across 99,224 rows); the pair `(review_id, order_id)` is | Reviews need a deduplication rule before you can say "one review per order" (Phase 3) |
| 99,441 `customer_id`s but only 96,096 `customer_unique_id`s | `customer_id` is a new id for every order. Repeat purchases **must** use `customer_unique_id` |
| `estimated_delivery_date` is always midnight | It's a date, so `days_vs_estimate` is whole days. This is the "discrete running variable" limitation in the RD analysis |
| ~3% of orders have no `delivered_at` | Not delivered yet, or canceled. Exclude these from the delivery metrics |
| 610 products have no category, and 2 categories have no English name | Fill in a fallback name when joining the translation (Phase 3) |
| 29 geolocation points fall outside Brazil | Filter them out or aggregate before using distance as a covariate (Phase 4) |

### Make sure you can answer
- Why is everything loaded as VARCHAR in `raw` and only cast in staging? (Hint: zip `01151`.)
- Why are staging models views and not tables?
- What does `{{ source('raw', 'orders') }}` give you that `raw.orders` doesn't?
- What exactly does dbt's `unique` test run against the database?
- Why can't a review be identified by `review_id` alone?

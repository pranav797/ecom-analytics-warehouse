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

---

## Phase 3: Core warehouse

### What happened
- **3 intermediate models** (views, in `models/intermediate/`). Each one holds logic that more
  than one mart needs, so it's written once:
  - `int_order_items_enriched`: items joined to product category (English, with a fallback) and
    seller state.
  - `int_order_delivery`: one row per order with `is_delivered`, `days_to_deliver`,
    `days_vs_estimate` (negative = early, 0 = on the promised day, positive = late) and
    `is_late`.
  - `int_order_reviews_dedup`: one review per order. The rule: keep the review **answered most
    recently**. The SQL comment and the YAML both explain the rejected alternatives.
- **4 marts** (tables, in `models/marts/`):
  - `fct_orders`: order grain, every status. It has items value, freight, payment, delivery
    timing, the deduplicated review score, and `is_review_before_delivery`.
  - `fct_order_items`: item grain, with seller and category.
  - `dim_sellers`: seller grain, with first and last sale, delivered orders and lifetime GMV.
  - `dim_customers`: **person** grain (`customer_unique_id`), with location from the latest
    order and order counts.
- Models now refer to each other with `{{ ref('model_name') }}`, the way staging refers to raw
  tables with `{{ source(...) }}`. That's how dbt knows the build order.
- **New kinds of tests**:
  - `relationships` (a foreign-key check): every `fct_order_items.order_id` exists in
    `fct_orders`, every `seller_id` exists in `dim_sellers`, and every
    `fct_orders.customer_unique_id` exists in `dim_customers`.
  - A **custom generic test**, `macros/test_expression_is_true.sql`. This is the template idea
    from Phase 2, written by hand. It powers the range checks: `price >= 0`,
    `delivered_at >= purchased_at`, and `is_delivered` matching `days_vs_estimate` being filled
    in.
  - A **singular test**, `tests/assert_row_counts_reconcile.sql`. It's a plain SQL file, not
    YAML, that compares raw row counts with staging and mart row counts and returns any table
    where they differ.

### Run it
```bash
cd warehouse && ../.venv/Scripts/dbt build; cd ..
```
You should see `PASS=74 WARN=0 ERROR=0`: 12 views + 4 tables + 58 tests. The warning about
unused configuration paths from Phase 2 is gone.

### Confirm the output
1. **Every schema is populated**. `staging` has 9 objects, `intermediate` 3, `marts` 4:
   ```bash
   .venv/Scripts/python -c "import duckdb; print(duckdb.connect('data/warehouse.duckdb', read_only=True).sql(\"SELECT table_schema, table_type, count(*) FROM information_schema.tables WHERE table_schema IN ('staging','intermediate','marts') GROUP BY ALL ORDER BY 1\"))"
   ```
2. **GMV adds up three different ways**. Each line should print **13,220,249**:
   ```bash
   .venv/Scripts/python -c "
   import duckdb; c = duckdb.connect('data/warehouse.duckdb', read_only=True)
   print(c.sql('SELECT sum(items_value) FROM marts.fct_orders WHERE is_delivered'))
   print(c.sql('SELECT sum(price) FROM marts.fct_order_items WHERE is_delivered'))
   print(c.sql('SELECT sum(lifetime_gmv) FROM marts.dim_sellers'))"
   ```
   If these ever disagree, a join is duplicating or dropping rows.
3. **Customer grain**. `dim_customers` has 96,096 rows (people), not 99,441 (orders). Only
   2,997 people ordered twice or more, about 3%. Repeat purchase is rare on Olist, which matters
   for the Phase 4 metric.
4. **Read the review deduplication** in `models/intermediate/int_order_reviews_dedup.sql`. Then
   find an order that had several reviews and compare the rows:
   ```bash
   .venv/Scripts/python -c "
   import duckdb; c = duckdb.connect('data/warehouse.duckdb', read_only=True)
   oid = c.sql('SELECT order_id FROM intermediate.int_order_reviews_dedup WHERE reviews_for_order = 3 LIMIT 1').fetchall()[0][0]
   print(c.sql(f\"SELECT review_id, review_score, review_answered_at FROM staging.stg_order_reviews WHERE order_id = '{oid}' ORDER BY review_answered_at\"))
   print(c.sql(f\"SELECT review_id, review_score FROM intermediate.int_order_reviews_dedup WHERE order_id = '{oid}'\"))"
   ```
   The kept review should be the last row of the first table.
5. **Break a relationship on purpose**. In `models/marts/fct_order_items.sql`, change
   `join {{ ref('fct_orders') }}` to `left join`, and in `fct_orders.sql` add
   `where o.order_status <> 'canceled'` as a new last line (after the final join). From
   `warehouse/`, run `../.venv/Scripts/dbt build --select +fct_order_items`. The `+` means
   "this model and everything upstream of it". The relationships test and the
   row-count test should both fail. Read their output, then undo both changes.
6. **Look at the lineage graph again** (`dbt docs generate` + `dbt docs serve`, same as Phase 2).
   Click `fct_orders` and look at how many upstream models feed it.

### A first look at the question (not the answer yet)
Average review score by `days_vs_estimate`, delivered orders only:

| days vs estimate | −3 | −2 | −1 | 0 | +1 | +2 | +3 |
|---|---|---|---|---|---|---|---|
| orders | 1,731 | 1,550 | 1,462 | 1,292 | 825 | 545 | 500 |
| avg review | 4.12 | 4.12 | 4.16 | 4.03 | 3.73 | 3.18 | 2.68 |

The scores fall right after 0. Whether that drop is *caused* by lateness, and how big it is with
a confidence interval, is Phase 4's job. Late orders overall average 2.27 against 4.29 for
on-time ones. That raw gap is bigger than the drop at the cutoff, because it mixes in everything
else that differs between late and on-time orders. That's exactly the confounding the RD design
avoids.

### Decisions made in this phase (you'll be asked about these)
| Decision | Why |
|---|---|
| Delivered = status `delivered` **and** `delivered_at` present | 8 "delivered" orders have no date and 6 canceled ones do. Neither status nor date alone is reliable |
| `days_vs_estimate` compares **dates**, not timestamps | The estimate is a date, so arriving at 9pm on the promised day counts as on time. On-time rate = 93.2% |
| Keep the most recently answered review | It's the customer's final word and keeps scores whole numbers (averaging would give 3.5) |
| GMV = item `price` only | Freight goes to the carrier, not the merchant. Payments also don't match items + freight on ~260 orders |
| `fct_orders` keeps every status | Canceled and unavailable orders matter for future funnel metrics. Filter with `is_delivered` |
| Customer location = latest order | A person can have several addresses. The latest is the best guess at where they live now |
| 4,977 reviews (5%) written before delivery are **flagged**, not dropped | Dropping them is an analysis decision, so Phase 4 decides and reports both versions |

### Make sure you can answer
- What's the difference between staging, intermediate and marts? Why does `int_order_delivery`
  exist instead of putting that logic inside `fct_orders`?
- What's the difference between `ref()` and `source()`?
- What's the difference between a generic test, a custom generic test and a singular test? When
  would you write each?
- Why is `dim_customers` keyed on `customer_unique_id`? What would the repeat purchase rate look
  like if it were keyed on `customer_id`?
- Why is the raw gap between late and on-time reviews (2.27 vs 4.29) **not** the causal effect
  of lateness?

---

## Phase 4: Metrics and causal analysis

### What happened, in plain words
1. **Three more summary tables** in `marts`:
   - `mart_seller_monthly`: one row per seller per month, with sales (GMV), orders, average order
     value, on-time rate and average review.
   - `mart_seller_cohorts`: groups sellers by the month of their first sale, then shows what share
     of them were still selling 1, 2, 3… months later.
   - `mart_delivery_reviews`: one row per "days early or late" value, with the average review.
     It's the table behind the RD chart.
2. **A repeat-purchase flag** on `dim_customers` (`is_repeat_within_180d`).
3. **Metric definitions written once**, in `models/marts/metrics.md`. The YAML points to them with
   `{{ doc("metric_gmv") }}`, so the same definition shows up on every model that uses it.
4. **A metric window** in `dbt_project.yml` (`vars:`): Jan 2017–Aug 2018, the complete months only.
5. **The analysis script** `analysis/rd_late_delivery.py`. It reads order-level data from DuckDB,
   runs 17 estimates, and saves them to a new table, **`analysis.rd_results`**. This is the first
   table that dbt doesn't create.
6. **The memo** `analysis/memo.md`: the answer, how sure we are, and what to do.

### The result in one sentence
Being late *at all* barely changes the average review. **Each extra day late costs about 0.6
stars**, so how late an order is matters far more than whether it crossed the promised date.

### Run it
```bash
cd warehouse && ../.venv/Scripts/dbt build; cd ..
.venv/Scripts/python analysis/rd_late_delivery.py
```
You should see `PASS=85` from dbt. The script prints a table of 17 rows (it takes about a minute)
and ends with `Wrote analysis.rd_results`. Each time dbt rebuilds the marts, rerun the script so
the results match.

### Confirm the output
1. **The headline numbers**:
   ```bash
   .venv/Scripts/python -c "import duckdb; print(duckdb.connect('data/warehouse.duckdb', read_only=True).sql(\"SELECT spec, outcome, round(estimate,3) est, round(ci_low,3) lo, round(ci_high,3) hi, round(p_value,3) p FROM analysis.rd_results WHERE spec IN ('main','kink (slope change)')\"))"
   ```
   The score row should show about −0.03 (not significant), and the kink row about −0.62
   (significant).
2. **See the shape yourself**. This is the chart the whole analysis is about:
   ```bash
   .venv/Scripts/python -c "import duckdb; print(duckdb.connect('data/warehouse.duckdb', read_only=True).sql('SELECT days_vs_estimate, orders, round(avg_review_score,2) avg FROM marts.mart_delivery_reviews WHERE days_vs_estimate BETWEEN -6 AND 8 ORDER BY 1'))"
   ```
   Left of 0 the scores stay flat around 4.1–4.3. Right of 0 they fall each day. That bend is the
   finding.
3. **Seller retention**. About 60% of new sellers sell again the next month, and about 47% six
   months later:
   ```bash
   .venv/Scripts/python -c "import duckdb; print(duckdb.connect('data/warehouse.duckdb', read_only=True).sql('SELECT months_since_first_sale k, round(sum(active_sellers)/sum(cohort_sellers),3) retention FROM marts.mart_seller_cohorts GROUP BY 1 ORDER BY 1 LIMIT 7'))"
   ```
4. **Repeat purchase rate**. Expect 1,095 repeaters out of 56,450 eligible customers, about 1.9%.
   The other ~40K customers are null: they're too recent to watch for 180 days, or have no
   delivered order.
   ```bash
   .venv/Scripts/python -c "import duckdb; print(duckdb.connect('data/warehouse.duckdb', read_only=True).sql('SELECT count(*) FILTER (WHERE is_repeat_within_180d) repeaters, count(is_repeat_within_180d) eligible, round(avg(is_repeat_within_180d::int),4) rate FROM marts.dim_customers'))"
   ```
5. **Read the metric docs** in the browser: run `dbt docs generate` and `dbt docs serve`, open
   `mart_seller_monthly`, and click the `gmv` column. You'll see the full GMV definition, including
   the rejected alternatives.
6. **Change the window on purpose**. In `dbt_project.yml`, set `metrics_start_month` to
   `"2018-01-01"` and run `dbt build --select mart_seller_cohorts`. There are now fewer cohorts, and
   the longest one has fewer months. Put it back afterwards.

### Words you'll need for interviews
| Term | Plain meaning here |
|---|---|
| **Running variable** | The number that decides who's "treated": days vs the promised date |
| **Cutoff** | 0.5, between "on the day" (0) and "1 day late" (+1) |
| **Bandwidth** | How many days on each side the estimate uses (about 4 here, chosen automatically) |
| **Level jump** | Does the score suddenly drop at the cutoff? About −0.03, so basically no |
| **Kink** | Does the *slope* change at the cutoff? Yes: from flat to −0.6 stars per day |
| **Placebo cutoff** | A fake cutoff (−5, +5) where nothing should happen. −5 passed; +5 failed because the curve flattens out there |
| **Covariate balance** | Things lateness can't cause (price, distance) shouldn't jump at the cutoff. They don't; freight is borderline |
| **Bunching** | Too many orders just before the deadline, which suggests rushing. Found: 36% fewer orders just after the cutoff than expected. This is the main weakness |
| **Robust CI** | The confidence interval from `rdrobust`, corrected for the bias of fitting a straight line |

### Decisions made in this phase
| Decision | Why |
|---|---|
| A repeat purchase must come **more than 24h** after the first order | 28% of "second orders" came within an hour: one cart split by seller |
| Customers too recent to observe for a full 180 days are left out (null), not counted as non-repeat | Otherwise recent customers would drag the rate down |
| Metric window Jan 2017–Aug 2018 | 2016 is sparse (November is missing) and Sep–Oct 2018 have no deliveries |
| Reviews written before delivery are **kept** in the main estimate | They're 70% of reviews at +3 days. Dropping them removes mostly late orders |
| Standard errors clustered by seller | One seller's reviews are related to each other, not independent |
| "Narrowest feasible" bandwidth of 2.6 days instead of half the optimal | With whole days, half the optimal (~1.9) leaves only one day per side |

### Make sure you can answer
- Why is "late orders average 2.27 vs 4.29 on time" not the causal effect?
- The direct day 0 vs day +1 comparison says −0.30, but the RD level jump says −0.03. Why do they
  differ, and which do you trust?
- What does the bunching result mean, and why does it hurt the level-jump estimate more than the
  kink estimate?
- Why does the +5 placebo fail, and does that undermine the main result?
- Why is repeat purchase defined with a 24h gap and a 180-day window?
- What does the memo recommend, and what experiment would test it?

---

## Phase 5: Dashboard and deploy

### What happened, in plain words
1. **`reports/` is now the dashboard**, built with Evidence. Each page is a Markdown file with SQL
   blocks and chart tags. Evidence runs the SQL and draws the charts.
2. **Data flows like this:**
   ```
   data/warehouse.duckdb ──export_db.py──▶ reports/sources/warehouse/warehouse.duckdb (older format)
        ──npm run sources──▶ small Parquet files (one per sources/warehouse/*.sql)
        ──npm run build──▶ reports/build/ (plain HTML/JS + Parquet; no server needed)
   ```
   The browser loads the Parquet files and queries them with a copy of DuckDB that runs inside
   the page. That's why the dropdowns on the Merchants page work without a server.
3. **Why the extra export step:** we use the old open-source Evidence, because the new one is a
   hosted product with no static build. The old one bundles an older DuckDB that can't open our
   newer file, so we hand it a copy saved in the older format.
4. **The pipeline file** `.github/workflows/build-deploy.yml` runs everything above on GitHub's
   servers on every push to `main`, then uploads `reports/build/` to Vercel.

### Run it
```bash
cd warehouse && ../.venv/Scripts/dbt build; cd ..
.venv/Scripts/python analysis/rd_late_delivery.py
.venv/Scripts/python reports/export_db.py
cd reports && npm run sources && npm run build:strict && npm run preview; cd ..
```
The last command serves the built site at http://localhost:3000. Press Ctrl+C to stop. For live
editing, use `npm run dev` instead; pages reload as you save.

### Confirm the output
1. **All 4 pages load**: Overview, Merchants, Delivery & Reviews, Findings. The headline tiles on
   Overview should read about 13.2M GMV, 96,203 orders and 93.2% on time.
2. **Filters work**. On Merchants, pick state `RJ`. The seller count and the table should shrink,
   with no page reload.
3. **Findings matches the memo**. The tiles should show −0.62 per day and −0.03 at the promised
   date, the same as `analysis/memo.md`.
4. **What's actually deployed**. Look inside `reports/build/data/warehouse/`. Each folder holds
   one tiny Parquet file, and that's all the data the public site gets: aggregates, not the raw
   orders.
5. **Break a page on purpose**. In `pages/index.md`, change `data={monthly_kpis}` to
   `data={monthly_kpi}` and run `npm run build:strict`. It fails with "not defined", which is how
   CI catches broken pages. Change it back.

### Make sure you can answer
- What does "static site" mean, and why does it never "sleep" like a Streamlit app?
- Where do the SQL queries run: at build time, in the browser, or both?
- Why does the pipeline export a second, older-format DuckDB file?
- Why can CI deploy to Vercel without Vercel ever seeing the Kaggle credentials?
- What would you lose by moving to the new Evidence Studio, and what would you gain?

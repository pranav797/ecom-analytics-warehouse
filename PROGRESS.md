# Progress log

The running record of the work: what was done, what didn't work, and what couldn't be done.
The newest phase is at the bottom. `CHECKS.md` explains how to verify each phase; this file
records what happened.

---

## Setup: repo structure and environment (2026-11-18)

**Done**
- Read `PLAN.md` and created the folder layout from §3, with `.gitkeep` files in empty folders.
- Added a `.gitignore` covering raw data, `*.duckdb`, dbt `target/`/`logs/`, Evidence
  `node_modules/`/`build/`, `.env`, and later dbt's `.user.yml`.
- Ran `git init` on branch `main`.
- Created `.venv` with **standard Python 3.13**.
- Installed and pinned in `requirements.txt`: dbt-core 1.12.7, dbt-duckdb 1.11.1, duckdb 2.0.0,
  pandas 3.1.1, statsmodels 0.15.0, rdrobust 2.1.1, kaggle 2.2.5 (scipy 1.18.1 added in Phase 4).
- Split the remaining work into 6 phases.

**Issues / deviations**
- The machine's default `py` launcher points at **free-threaded Python 3.13t**, which many packages
  don't support yet. The venv was made explicitly with `py -V:3.13`.
- `PLAN.md` §7 mentions `analysis/experiment_design.md`, but the §3 folder layout doesn't list it.
  It's treated as a stretch item.

---

## Phase 1: Raw data in DuckDB, commit `fb01831`

**Done**
- `ingest/load_raw.py` downloads the dataset with the Kaggle API if `data/raw/` is empty, then
  loads all 9 CSVs into the `raw` schema of `data/warehouse.duckdb`, **all as VARCHAR**. The path
  can be overridden with `WAREHOUSE_PATH`.
- Row counts match the published dataset: orders 99,441; items 112,650; payments 103,886;
  reviews 99,224; customers 99,441; products 32,951; sellers 3,095; geolocation 1,000,163;
  category translation 71.
- License checked on the Kaggle page: **CC BY-NC-SA 4.0**. The attribution and the
  non-commercial / share-alike note are in the README.

**Issues / deviations**
- The first run failed because there were no Kaggle credentials. The user logged in with
  `kaggle auth login`.
- **The plan's CI secrets are out of date.** kaggle 2.x uses a single `KAGGLE_API_TOKEN`, not
  `KAGGLE_USERNAME` / `KAGGLE_KEY`. The CI workflow needs to follow that.
- **DuckDB 2.0 API change:** `con.sql(...)` results no longer have `.fetchone()`, and an
  unfinished `con.execute(...)` result blocks the next query on that connection. Snippets use
  `.sql(...).fetchall()`.

---

## Phase 2: dbt project and staging layer, commit `e6064e4`

**Done**
- Set up `warehouse/dbt_project.yml` and `profiles.yml` (dbt-duckdb, same `WAREHOUSE_PATH`
  default).
- Added a `generate_schema_name` macro so the schemas are `staging`/`intermediate`/`marts`, not
  `main_staging`.
- Registered the 9 raw tables as sources and wrote 9 `stg_*` views that only rename and cast.
- Added 30 tests: primary keys, composite keys (written as `col || '-' || col` expressions) and
  accepted values. `dbt build`: **PASS=39**.
- Created `CHECKS.md`, with one section per phase from here on.

**Findings from profiling**
- `review_id` is not unique (98,410 ids / 99,224 rows); the pair `(review_id, order_id)` is.
- 99,441 `customer_id`s but 96,096 `customer_unique_id`s.
- The estimated delivery date is always midnight, so it's cast to DATE.
- 610 products have no category, and 2 categories have no translation.
- 29 geolocation points fall outside Brazil.

**Issues / deviations**
- dbt warned about unused config paths, because `intermediate/` and `marts/` were still empty.
  The warning went away in Phase 3.

---

## Phase 3: Intermediate models and core marts, commit `dcb3787`

**Done**
- `int_order_items_enriched`: English category, falling back to Portuguese and then `unknown`.
- `int_order_delivery`: `is_delivered`, `days_vs_estimate`, `is_late`.
- `int_order_reviews_dedup`: keeps the most recently answered review.
- `fct_orders`, `fct_order_items`, `dim_sellers`, and `dim_customers` (person grain).
- Tests:
  - relationships between tables
  - a custom generic test, `expression_is_true`, for range checks
  - a singular test reconciling raw and model row counts
- `dbt build`: **PASS=74**.
- Sanity checks: GMV = **13,220,249** from orders, items and sellers alike. On-time rate 93.2%.

**Decisions**
- Delivered = status `delivered` **and** `delivered_at` present (8 + 6 orders where status and date
  disagree).
- `days_vs_estimate` compares dates, not timestamps.
- GMV = item price only. Payments don't match items + freight on ~260 orders.
- 4,977 reviews written before delivery are flagged, not dropped.

**Issues / deviations**
- A `CHECKS.md` snippet failed under DuckDB 2.0 (an unfinished `execute()` result). Fixed and
  re-tested.
- The "break it on purpose" instructions first said to put the `where` clause in the wrong place.
  Corrected.

---

## Phase 4: Metrics and causal analysis, commit `46f830b`

**Done**
- `mart_seller_monthly`, `mart_seller_cohorts`, `mart_delivery_reviews`.
- `is_repeat_within_180d` on `dim_customers`: **1.94%** (1,095 / 56,450 eligible).
- Metric definitions as dbt doc blocks in `models/marts/metrics.md`, with rejected alternatives.
- Metric window set with dbt `vars`: 2017-01 to 2018-08 (complete months).
- `dbt build`: **PASS=85**.
- `analysis/rd_late_delivery.py`: 17 estimates written to `analysis.rd_results`, with standard
  errors clustered by seller.
- `analysis/memo.md`: the decision memo.

**Results**
- Level jump at the promised date: **−0.03 stars** (CI −0.18 to +0.12), not significant.
- 5-star share: **−7.9 pp** (CI −12.5 to −3.2).
- **Kink:** each extra day late costs **−0.62 stars/day** (CI −0.73 to −0.52).
- Raw day 0 vs day +1: −0.30 stars.
- Seller retention: 60% at 1 month, 47% at 6 months.

**Things that didn't work or couldn't be done**
- **Half-bandwidth robustness check was impossible.** With whole-day data, h ≈ 1.9 leaves one mass
  point per side, and `rdrobust` raised "Not enough distinct running-variable values". It was
  replaced with the narrowest feasible bandwidth, h = 2.6.
- **The +5-day placebo failed** (−0.35, p = 0.02). The curve flattens around day 6 and a local line
  can't follow the bend. This is reported in the memo, not hidden.
- **Bunching check failed:** 36% fewer orders just after the cutoff than the trend predicts
  (p = 0.001). This is the main threat to validity and is reported in the memo.
- The first version reported the **conventional** estimate next to the **robust** CI, so some
  estimates sat outside their own CI. It now reports the bias-corrected estimate, with the
  conventional one in `estimate_conventional`.
- The level-jump estimate for the **1-star** share (−0.037, p = 0.04) points the "wrong" way.
  Treated as fragile: one of 17 tests.
- The freight covariate is borderline unbalanced (p = 0.08).

**Decisions**
- Repeat purchase requires a gap of **more than 24h**: 797 of 2,801 "second orders" were within an
  hour, i.e. split carts. Customers who can't be observed for the full 180 days are null.
- Reviews written before delivery are **kept** in the main RD estimate. At +3 days, 70% of reviews
  come before delivery, so dropping them is not neutral.
- The power analysis / experiment design is **not done**. It's a stretch goal, as in the plan.

---

## Phase 5: Dashboard and deploy (done)

**Done**
- Logging: created this `PROGRESS.md`, covering setup through Phase 4.
- `reports/` is an Evidence project with **4 pages**: Overview, Merchants, Delivery & Reviews,
  Findings. Every page carries the CC BY-NC-SA attribution footer.
- 6 source queries in `reports/sources/warehouse/*.sql`, all built from the marts and
  `analysis.rd_results`.
- `reports/export_db.py` copies the `marts` and `analysis` schemas into
  `reports/sources/warehouse/warehouse.duckdb` in **DuckDB 1.4 format**.
- Added `customer_state` to `fct_orders` for the on-time-by-state chart. `dbt build` still
  PASS=85.
- The strict build passes (`npm run sources:strict`, `npm run build:strict`). Previewed all 4
  pages in a browser with no console errors.
- The Findings page reads its headline numbers live from `rd_results`, so the page and the
  analysis can't drift apart.
- `.github/workflows/build-deploy.yml`: ingest → dbt build → RD analysis → export → Evidence
  build → Vercel deploy. The deploy step is skipped until the Vercel secrets exist.
- `.claude/launch.json`: a `dashboard-preview` config that serves `reports/build` on port 3000.

**Things that didn't work or couldn't be done**
- **The Evidence the plan assumes no longer exists as the default.** `degit evidence-dev/template`
  now gives "Evidence Studio": a hosted product with a new CLI, ClickHouse SQL, an account
  requirement, and **no static build**. The user chose to stay on **legacy open-source Evidence
  v40.1.8**, taken from the template commit `4b13d42` (2026-02-06). Risk: that version is no
  longer developed.
- **Legacy Evidence can't read our DuckDB file.** Its connector uses DuckDB 1.4, which rejects
  files written by 2.0. Fix: `export_db.py` writes a copy with `storage_version 'v1.4.0'`. Tested
  with `@duckdb/node-api` 1.4 before building on it.
  - First attempt at the export failed: attaching from a read-only connection makes the new file
    read-only too. It now uses an in-memory connection.
- **`npm install` silently installed nothing.** The template's `.npmrc` hides errors. The real
  error was a peer-dependency conflict: npm now resolves TypeScript 7, and Evidence 40 needs
  TypeScript 5. Fixed by pinning `typescript@5` as a dev dependency. (Deleting the template's
  lock file is what exposed it.)
- **Build errors fixed on the way:**
  - components can't take `data={warehouse.table}` directly, so each page defines a named query
    first
  - a query named `r` broke the Svelte compile, so it was renamed `results`
- **The heatmap axes were unsorted** (0, 10, 12, 11…). Fixed with `xSort` / `ySort`.
- **Inline numbers lost their spaces.** `<Value>` components at the start of a line lost the
  space before them. Rewritten so each one sits mid-line. A leftover cosmetic quirk: Evidence
  renders a space before `)` and `.` after an inline value.
- **`evidence preview` mangles arguments** (`--port` and `-l` both failed), so the preview uses
  the default port 3000.
- **The Cloudflare Pages fallback from the plan won't work.** The build has two DuckDB-WASM files
  of 34 MB and 39 MB, over Cloudflare's 25 MB per-file limit. Vercel and Netlify are fine. The
  data Parquet files are tiny (max 118 KB). Total build: 89 MB.
- Created the **public** repo https://github.com/pranav797/ecom-analytics-warehouse and pushed
  `main`. Checked first that no data files or tokens were in the commit.
- **Not done yet; needs the user:** add the `KAGGLE_API_TOKEN` secret, create the Vercel project
  and add `VERCEL_TOKEN` / `VERCEL_ORG_ID` / `VERCEL_PROJECT_ID`, then see the first green run
  and the live URL.
- Right after the push, `gh run list` showed no run yet, and the repo had no secrets. The first
  run is expected to fail at the Kaggle download until `KAGGLE_API_TOKEN` is added.
- **First green CI run** (run 44440229486, 1m29s): every step passed on Ubuntu, and the results
  match local exactly (99,441 orders, dbt PASS=85, kink −0.624, 6 Evidence sources). The deploy
  step was skipped because `VERCEL_PROJECT_ID` wasn't set yet.
- The two runs before it failed at the Kaggle download. They ran before `KAGGLE_API_TOKEN` was
  added, as expected.
- Hardened the deploy step to require **all three** Vercel secrets. With only the token, the
  Vercel CLI would have created a new project instead of deploying to the user's one.
- GitHub warned that the actions ran on deprecated Node 20. Bumped checkout, setup-python and
  setup-node to v7, which run on Node 24.
- The Vercel project was created from the GitHub import with preset "Other" and no build command.
  The Git connection should be disconnected so Vercel doesn't redeploy the raw repo on every push.
- **`VERCEL_ORG_ID` confusion:** the user removed it, thinking a Hobby account has no org. The
  Vercel CLI requires it alongside the project ID. A Hobby account's scope ("pranav797's
  projects") is a team, and its Team ID is the org ID. Read here from a Vercel API error response
  and set as the secret with the user's OK. The ID itself is kept out of the repo.
- The Node 24 action versions ran green with no deprecation warning (run 44440525767).
- **First deploy:** run 44440878431, triggered by hand. Every step passed, including the deploy.
  **Live at https://ecom-analytics-warehouse.vercel.app.** All 4 pages return HTTP 200 publicly,
  and the Findings page renders its numbers from the deployed Parquet files with no console
  errors.
- The Vercel Git connection was still on after setup (the user's screenshot showed "Connected").
  The pipeline's deploy happened to land last, so the live site was unaffected. The user then
  **disconnected** it, so only GitHub Actions deploys now.

---

## Phase 6: Ship (MVP)

**Done**
- Rewrote `README.md` for someone reading the repo for the first time:
  - live link and the headline result
  - a mermaid architecture diagram and the stack
  - the warehouse layers with model and test counts, and a metric definitions table
  - the analysis, including the failed checks
  - how to run it locally, the repo layout, design notes, and the license
- Filled in the resume entry in `PLAN.md` §11 with real numbers: **99K orders, 19 models,
  66 tests, −0.62 stars per day late (95% CI 0.52–0.73)**, plus a shorter variant.
- Counts taken from `dbt ls`, not estimated: 19 models, 66 tests.

**Not done (stretch, per plan)**
- Experiment design + power analysis (`analysis/experiment_design.md`, `power_analysis.py`).
- Reusable A/B module validated on Cookie Cats.
- Seller funnel with the Marketing Funnel dataset.
- Moving the warehouse to BigQuery.

---

## Repo cleanup

- Scanned every tracked file and the full git history. There were **no credentials or tokens**,
  and every commit uses the GitHub noreply email.
- **Stopped tracking `.claude/`** (local preview config) and **`.vscode/settings.json`** (personal
  editor setting, picked up by `git add -A` in Phase 3). Both are now in `.gitignore` and still
  exist locally.
- Removed the Vercel team ID from this file. It's an identifier, not a credential, but there's no
  reason for it to be public.
- **Still in git history:** the old commits still contain these files and the team ID. Removing
  them for good needs a history rewrite and a force-push. Not done without the user's go-ahead.

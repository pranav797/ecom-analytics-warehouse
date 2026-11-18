# E-Commerce Analytics Warehouse

See [PLAN.md](PLAN.md) for the full plan.

## Setup

```bash
py -3.13 -m venv .venv
.venv/Scripts/pip install -r requirements.txt
.venv/Scripts/python ingest/load_raw.py
```

`load_raw.py` downloads the dataset with the Kaggle API when `data/raw/` is empty, so it needs
Kaggle credentials: run `.venv/Scripts/kaggle auth login`, or set `KAGGLE_API_TOKEN` to a token from
https://www.kaggle.com/settings/api. The DuckDB file goes to
`data/warehouse.duckdb` unless `WAREHOUSE_PATH` is set.

## Data & license

Data: [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce),
by Olist, licensed [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).
Derived tables and dashboard data in this project are shared under the same license, for non-commercial use.

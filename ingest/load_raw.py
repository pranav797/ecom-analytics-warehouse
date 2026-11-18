"""Download the Olist CSVs (if missing) and load each into DuckDB's `raw` schema.

Everything is loaded as VARCHAR on purpose: type casting belongs in dbt staging,
and auto-inference would e.g. strip leading zeros from zip code prefixes.
"""
import os
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "data" / "raw"
DB_PATH = os.environ.get("WAREHOUSE_PATH", str(ROOT / "data" / "warehouse.duckdb"))
DATASET = "olistbr/brazilian-ecommerce"


def download():
    # Imported lazily: the kaggle package authenticates on import and fails without credentials.
    from kaggle.api.kaggle_api_extended import KaggleApi

    api = KaggleApi()
    api.authenticate()
    api.dataset_download_files(DATASET, path=str(RAW_DIR), unzip=True)


def table_name(csv: Path) -> str:
    # olist_order_items_dataset.csv -> order_items
    return csv.stem.removeprefix("olist_").removesuffix("_dataset")


def main():
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    if not list(RAW_DIR.glob("*.csv")):
        print(f"Downloading {DATASET} ...")
        download()

    csvs = sorted(RAW_DIR.glob("*.csv"))
    if len(csvs) != 9:
        raise SystemExit(f"Expected 9 CSVs in {RAW_DIR}, found {len(csvs)}")

    con = duckdb.connect(DB_PATH)
    con.execute("CREATE SCHEMA IF NOT EXISTS raw")
    for csv in csvs:
        name = table_name(csv)
        con.execute(
            f"CREATE OR REPLACE TABLE raw.{name} AS "
            "SELECT * FROM read_csv(?, header = true, all_varchar = true)",
            [str(csv)],
        )
        rows = con.execute(f"SELECT count(*) FROM raw.{name}").fetchone()[0]
        print(f"raw.{name:<34} {rows:>9,}")
    con.close()


if __name__ == "__main__":
    main()

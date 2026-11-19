"""Copy the marts and analysis schemas into reports/sources/warehouse/warehouse.duckdb, in DuckDB 1.4 format.

Why: the pipeline uses DuckDB 2.0, but Evidence's DuckDB connector is built on DuckDB 1.4,
which can't open 2.0 files. DuckDB 2.0 can write the older storage format on request.
"""
import os
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
SRC = os.environ.get("WAREHOUSE_PATH", str(ROOT / "data" / "warehouse.duckdb"))
OUT = Path(__file__).resolve().parent / "sources" / "warehouse" / "warehouse.duckdb"
SCHEMAS = ["marts", "analysis"]

OUT.unlink(missing_ok=True)
con = duckdb.connect()
con.execute("attach ? as src (read_only)", [SRC])
con.execute(f"attach '{OUT.as_posix()}' as out (storage_version 'v1.4.0')")
for schema in SCHEMAS:
    con.execute(f"create schema out.{schema}")
    tables = con.sql(
        "select table_name from duckdb_tables() where database_name = 'src' and schema_name = ?", params=[schema]
    ).fetchall()
    for (t,) in tables:
        con.execute(f"create table out.{schema}.{t} as select * from src.{schema}.{t}")
        print(f"{schema}.{t}")
con.close()
print(f"Wrote {OUT}")

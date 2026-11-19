# Dashboard (Evidence)

Legacy open-source Evidence (v40), pinned because newer Evidence is a hosted product without a static build.

```bash
../.venv/Scripts/python export_db.py   # marts + analysis -> sources/warehouse/warehouse.duckdb (DuckDB 1.4 format)
npm install
npm run sources                        # run sources/warehouse/*.sql, cache results as Parquet
npm run dev                            # local preview
npm run build                          # static site in build/
```

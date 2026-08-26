"""
Run every compiled analysis against the local DuckDB database and print
the results.

dbt compiles analyses but does not execute them, so this reads the compiled
SQL from target/ and runs it.

Usage (from the project directory, after dbt compile):
    python scripts/run_analyses.py
"""

import glob
import os
import sys

import duckdb

PROJECT_NAME = "podcast_analytics"
DATABASE = "dev.duckdb"
COMPILED_DIR = os.path.join("target", "compiled", PROJECT_NAME, "analyses")
MAX_ROWS = 25


def main():
    if not os.path.exists(DATABASE):
        sys.exit(f"{DATABASE} not found. Run this from the project directory.")

    if not os.path.isdir(COMPILED_DIR):
        sys.exit(f"{COMPILED_DIR} not found. Run 'dbt compile' first.")

    paths = sorted(glob.glob(os.path.join(COMPILED_DIR, "*.sql")))
    if not paths:
        sys.exit("No compiled analyses found.")

    con = duckdb.connect(DATABASE, read_only=True)
    failures = []

    for path in paths:
        name = os.path.basename(path)
        print("\n" + "=" * 78)
        print(name)
        print("=" * 78)

        with open(path, encoding="utf-8") as handle:
            sql = handle.read()

        try:
            df = con.execute(sql).df()
        except Exception as error:
            print(f"  ERROR: {error}")
            failures.append(name)
            continue

        if df.empty:
            print("  (no rows)")
            continue

        with_pandas_options(df)

    con.close()

    if failures:
        sys.exit(f"\n{len(failures)} analyses failed: {', '.join(failures)}")


def with_pandas_options(df):
    import pandas as pd

    with pd.option_context(
        "display.max_rows", MAX_ROWS,
        "display.max_columns", None,
        "display.width", 200,
    ):
        print(df.head(MAX_ROWS).to_string(index=False))
        if len(df) > MAX_ROWS:
            print(f"  ... {len(df) - MAX_ROWS} more rows")


if __name__ == "__main__":
    main()

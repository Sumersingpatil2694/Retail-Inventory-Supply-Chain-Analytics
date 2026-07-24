"""
Retail Analytics - Data Loader
--------------------------------
Loads all dimension + fact CSVs into the retail_analytics MySQL database
created by schema.sql, in the correct FK dependency order:
    warehouses -> stores -> suppliers -> products -> fact_sales_inventory

Usage:
    1. Run schema.sql in MySQL first (creates empty tables).
    2. pip install pandas sqlalchemy pymysql
    3. Set the DB_PASSWORD environment variable (see below) - do NOT hardcode it.
    4. Set FACT_CSV to point at whichever cleaned fact CSV you want to load.
    5. python load_data.py

Setting the password (PowerShell, current session only):
    $env:DB_PASSWORD = "your_mysql_password"
    python load_data.py

Setting it permanently (Windows, all future terminals):
    setx DB_PASSWORD "your_mysql_password"
    (then open a NEW terminal for it to take effect)
"""

import os
from pathlib import Path
from urllib.parse import quote_plus
import pandas as pd
from sqlalchemy import create_engine, text

# ----------------------------------------------------------------------------
# CONFIG - edit these before running
# ----------------------------------------------------------------------------

DB_CONFIG = {
    "user": "root",
    "password": os.getenv("DB_PASSWORD"),  # never hardcode - set via env var
    "host": "localhost",
    "port": 3306,
    "database": "retail_analytics",
}

# All CSVs (dimensions + fact) live inside the data/ folder
DATA_DIR = Path("data")

# Pick ONE of the two fact CSVs:
#   - "fact_sales_inventory_CLEAN_reference.csv"  (9,000 rows, shipped reference)
#   - "fact_sales_inventory_CLEANED.csv"           (9,003 rows, fresh notebook export)
FACT_CSV = DATA_DIR / "fact_sales_inventory_CLEAN_reference.csv"

# ----------------------------------------------------------------------------

def get_engine():
    if not DB_CONFIG["password"]:
        raise RuntimeError(
            "DB_PASSWORD environment variable is not set.\n"
            "PowerShell:  $env:DB_PASSWORD = \"your_mysql_password\"\n"
            "Then re-run: python load_data.py"
        )
    safe_password = quote_plus(DB_CONFIG["password"])
    url = (
        f"mysql+pymysql://{DB_CONFIG['user']}:{safe_password}"
        f"@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']}"
    )
    return create_engine(url)


def load_table(engine, csv_path: Path, table_name: str, dtype_overrides=None):
    """Load a CSV into a table, appending to the existing schema (no DDL changes)."""
    df = pd.read_csv(csv_path)

    if dtype_overrides:
        for col, fn in dtype_overrides.items():
            if col in df.columns:
                df[col] = fn(df[col])

    df.to_sql(
        table_name,
        con=engine,
        if_exists="append",
        index=False,
        method="multi",
        chunksize=1000,
    )
    print(f"  -> {table_name}: {len(df):,} rows loaded from {csv_path.name}")


def truncate_all(engine):
    """Wipe existing rows before a fresh load, respecting FK order (child first)."""
    tables_in_delete_order = [
        "fact_sales_inventory",
        "products",
        "suppliers",
        "stores",
        "warehouses",
    ]
    with engine.begin() as conn:
        conn.execute(text("SET FOREIGN_KEY_CHECKS = 0"))
        for t in tables_in_delete_order:
            conn.execute(text(f"TRUNCATE TABLE {t}"))
        conn.execute(text("SET FOREIGN_KEY_CHECKS = 1"))
    print("Existing data truncated.\n")


def main():
    engine = get_engine()

    # Sanity check connection
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    print(f"Connected to database: {DB_CONFIG['database']}\n")

    truncate_all(engine)

    print("Loading dimension tables (parent -> child order)...")
    load_table(engine, DATA_DIR / "warehouses.csv", "warehouses")
    load_table(engine, DATA_DIR / "stores.csv", "stores")
    load_table(engine, DATA_DIR / "suppliers.csv", "suppliers")
    load_table(engine, DATA_DIR / "products.csv", "products")

    print("\nLoading fact table...")
    load_table(
        engine,
        FACT_CSV,
        "fact_sales_inventory",
        dtype_overrides={
            # id is AUTO_INCREMENT in schema - drop it if present in the CSV
        },
    )

    print("\nRow count verification:")
    with engine.connect() as conn:
        for t in ["warehouses", "stores", "suppliers", "products", "fact_sales_inventory"]:
            count = conn.execute(text(f"SELECT COUNT(*) FROM {t}")).scalar()
            print(f"  {t}: {count:,} rows")

    print("\nDone.")


if __name__ == "__main__":
    main()
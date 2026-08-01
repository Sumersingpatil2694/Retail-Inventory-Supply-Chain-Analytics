# export_datasets.py
#
# Dumps every view in retail_analytics to its own CSV so I can just
# plug it into Tableau / Excel pivots without doing any more joins
# or grouping on that side - everything's already aggregated at the
# right level (monthly, category, store, supplier etc).
#
# How to run:
#   1. schema.sql and views.sql should already be run, and data loaded
#      (Mysql_data_loader.py handles that part).
#   2. Set DB_PASSWORD, either way works (same as the loader script):
#        a) copy .env.example -> .env and put DB_PASSWORD=... in there
#           (this is gitignored, gets picked up automatically below)
#        b) or just export it as a real env var:
#           PowerShell:  $env:DB_PASSWORD = "your_mysql_password"
#           macOS/Linux: export DB_PASSWORD="your_mysql_password"
#   3. python export_datasets.py
#
# Output goes to ./SQL_data/<view_name>.csv

import os
import sys
import logging
from pathlib import Path
from urllib.parse import quote_plus

import pandas as pd
from sqlalchemy import create_engine, text

try:
    from dotenv import load_dotenv
    load_dotenv()  # picks up a local .env if there is one, never commit that file
except ImportError:
    pass  # dotenv isn't required, a normal env var works fine without it

# ---------------------------------------------------------------------------
# config
# ---------------------------------------------------------------------------

DB_CONFIG = {
    "user": "root",
    "password": os.environ.get("DB_PASSWORD", ""),
    "host": "localhost",
    "port": 3306,
    "database": "retail_analytics",
}

OUTPUT_DIR = Path("SQL_data")

# every view we want exported, roughly in the order you'd build a dashboard
# keeping file names simple (no "vw_" prefix) since these are for
# Tableau/Excel, not meant to be read as SQL object names
VIEWS_TO_EXPORT = {
    "vw_monthly_kpi_summary": "monthly_kpi_summary.csv",
    "vw_quarterly_growth": "quarterly_growth.csv",
    "vw_category_kpi": "category_kpi.csv",
    "vw_store_ranking": "store_ranking.csv",
    "vw_supplier_performance": "supplier_performance.csv",
    "vw_abc_classification": "abc_classification.csv",
    "vw_inventory_turnover": "inventory_turnover.csv",
    "vw_dead_stock": "dead_stock.csv",
    "vw_stockout_overstock": "stockout_overstock.csv",
    "vw_reorder_recommendation": "reorder_recommendation.csv",
    "vw_warehouse_performance": "warehouse_performance.csv",
    "vw_regional_performance": "regional_performance.csv",
}

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-7s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# functions
# ---------------------------------------------------------------------------

def get_engine():
    """Set up the SQLAlchemy engine for MySQL."""
    if not DB_CONFIG["password"]:
        logger.error(
            "DB_PASSWORD environment variable is not set.\n"
            "  PowerShell:  $env:DB_PASSWORD = \"your_mysql_password\"\n"
            "  macOS/Linux: export DB_PASSWORD=\"your_mysql_password\""
        )
        raise RuntimeError("DB_PASSWORD environment variable is not set.")

    safe_password = quote_plus(DB_CONFIG["password"])
    url = (
        f"mysql+pymysql://{DB_CONFIG['user']}:{safe_password}"
        f"@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']}"
    )
    engine = create_engine(url, pool_pre_ping=True)
    logger.info(f"Database engine created for: {DB_CONFIG['database']}")
    return engine


def export_view(engine, view_name: str, file_name: str) -> int:
    """Pull one view out to CSV, return how many rows it wrote."""
    df = pd.read_sql(text(f"SELECT * FROM {view_name}"), engine)
    out_path = OUTPUT_DIR / file_name
    df.to_csv(out_path, index=False)
    logger.info(f"  [OK] {view_name} -> {out_path}  ({len(df):,} rows, {len(df.columns)} cols)")
    return len(df)


def main():
    logger.info("=" * 60)
    logger.info("Retail Analytics — Dashboard Dataset Exporter")
    logger.info("=" * 60)

    OUTPUT_DIR.mkdir(exist_ok=True)
    engine = get_engine()

    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    logger.info(f"Connected to database: {DB_CONFIG['database']}\n")

    logger.info(f"Exporting {len(VIEWS_TO_EXPORT)} views to '{OUTPUT_DIR}/'...")
    total_rows = 0
    failures = []
    for view_name, file_name in VIEWS_TO_EXPORT.items():
        try:
            total_rows += export_view(engine, view_name, file_name)
        except Exception as e:
            logger.error(f"  [FAIL] {view_name}: {e}")
            failures.append(view_name)

    logger.info("")
    logger.info("=" * 60)
    if failures:
        logger.warning(f"Done with errors — {len(failures)} view(s) failed: {failures}")
    else:
        logger.info(f"All views exported successfully. Total rows written: {total_rows:,}")
    logger.info(f"Files are in: {OUTPUT_DIR.resolve()}")
    logger.info("=" * 60)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)

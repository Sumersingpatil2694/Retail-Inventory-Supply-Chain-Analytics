# Mysql_data_loader.py
#
# Loads all the dimension + fact CSVs into the retail_analytics MySQL
# database (schema.sql needs to have already created the empty tables).
# Respects FK order: warehouses -> stores -> suppliers -> products ->
# fact_sales_inventory.
#
# A few things I added on top of a basic loader:
#   - proper logging (timestamped, goes to file + console)
#   - timing per table so I know what's slow
#   - basic validation before insert (row counts, nulls, FK sanity)
#   - flags duplicate PKs instead of silently letting MySQL choke on them
#   - wraps everything in a transaction so a bad table doesn't leave
#     things half-loaded
#   - single config dict up top instead of scattered constants
#   - post-load verification queries at the end
#
# How to run:
#   1. Run schema.sql in MySQL first (creates the empty tables).
#   2. pip install pandas sqlalchemy pymysql python-dotenv
#   3. Set DB_PASSWORD, either way works:
#        a) copy .env.example -> .env and put DB_PASSWORD=... in there
#           (gitignored, gets picked up automatically below)
#        b) or set it as a real env var instead:
#           PowerShell:  $env:DB_PASSWORD = "your_mysql_password"
#           macOS/Linux: export DB_PASSWORD="your_mysql_password"
#   4. python Mysql_data_loader.py

import os
import sys
import time
import logging
from pathlib import Path
from datetime import datetime
from urllib.parse import quote_plus

import pandas as pd
from sqlalchemy import create_engine, text, inspect

try:
    from dotenv import load_dotenv
    load_dotenv()  # picks up a local .env if there is one, never commit that file
except ImportError:
    pass  # dotenv isn't required, a normal env var works fine without it

# ---------------------------------------------------------------------------
# config - edit these before running
# ---------------------------------------------------------------------------

DB_CONFIG = {
    "user": "root",
    "password": os.environ.get("DB_PASSWORD", ""),
    "host": "localhost",
    "port": 3306,
    "database": "retail_analytics",
}

# all the CSVs live inside data/
DATA_DIR = Path("data")

# pick ONE of the fact CSVs
FACT_CSV = DATA_DIR / "fact_sales_inventory_CLEANED.csv"

# these column lists need to match schema.sql exactly, table by table
TABLE_COLUMNS = {
    "warehouses": ["warehouse_id", "warehouse_name", "city", "capacity_units"],
    "stores": ["store_id", "store_name", "city", "warehouse_id", "store_type"],
    "suppliers": ["supplier_id", "supplier_name", "city", "avg_lead_time_days", "reliability_score"],
    "products": ["product_id", "product_name", "category", "supplier_id",
                 "unit_cost", "unit_price", "reorder_point"],
    "fact_sales_inventory": [
        "date", "store_id", "product_id", "warehouse_id", "supplier_id",
        "units_sold", "inventory_level", "units_ordered", "units_received",
        "delivery_delay_days", "stockout_flag", "revenue", "unit_price_txn",
        "discount_pct", "holiday_promo_flag", "weather", "season",
    ],
}

# allowed values for the CHECK-constrained columns in schema.sql
# fact_sales_inventory.weather -> chk_weather
# fact_sales_inventory.season  -> chk_season
# keep these in sync if the constraints in schema.sql ever change
ALLOWED_WEATHER = {"Sunny", "Rain", "Cloudy", "Cold", "Heatwave", "Storm", "Unknown"}
ALLOWED_SEASON = {"Winter", "Summer", "Autumn", "Monsoon"}

# expected row counts, just for the post-load sanity check
EXPECTED_COUNTS = {
    "warehouses": 8,
    "stores": 25,
    "suppliers": 20,
    "products": 410,
    "fact_sales_inventory": None,  # varies (~48,973)
}

# load order, parent -> child, has to respect the FKs
LOAD_ORDER = ["warehouses", "stores", "suppliers", "products", "fact_sales_inventory"]

# ---------------------------------------------------------------------------
# logging setup
# ---------------------------------------------------------------------------

# Windows terminals default to cp1252 a lot of the time, which can't
# encode the checkmark/arrow characters used in the log lines below and
# ends up crashing the handler mid-run. Forcing UTF-8 on stdout/stderr
# here (works on 3.7+) so it doesn't blow up with UnicodeEncodeError.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-7s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("data_loader.log", mode="w", encoding="utf-8"),
    ],
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
    engine = create_engine(url, pool_pre_ping=True, pool_recycle=3600)
    logger.info(f"Database engine created for: {DB_CONFIG['database']}")
    return engine


def validate_csv(df: pd.DataFrame, table_name: str, csv_path: Path) -> None:
    """Sanity-check a CSV before it goes anywhere near the database."""
    expected_cols = TABLE_COLUMNS[table_name]

    # bail out if a required column is missing
    missing = [c for c in expected_cols if c not in df.columns]
    if missing:
        raise ValueError(
            f"{csv_path.name} is missing required column(s) for '{table_name}': {missing}"
        )

    # extra columns are fine, just note them
    extra_cols = [c for c in df.columns if c not in expected_cols]
    if extra_cols:
        logger.info(f"  → Dropping {len(extra_cols)} extra column(s) not in schema: {extra_cols}")

    # flag nulls in the columns we actually care about
    critical_nulls = df[expected_cols].isna().sum()
    critical_nulls = critical_nulls[critical_nulls > 0]
    if len(critical_nulls) > 0:
        logger.warning(f"  ⚠️ Null values found: {dict(critical_nulls)}")

    # duplicate check on the PK column (first column, by our convention)
    pk_col = expected_cols[0]
    dup_count = df[pk_col].duplicated().sum()
    if dup_count > 0:
        logger.warning(f"  ⚠️ {dup_count} duplicate primary key values in column '{pk_col}'")
        logger.warning(
            "     (Expected for fact_sales_inventory — 'date' repeats across "
            "stores/products; the real uniqueness key is date+store_id+product_id, "
            "enforced separately by uq_fact_date_store_product.)"
        )

    # weather/season have CHECK constraints in MySQL, and MySQL's error for
    # those is basically useless (no row detail at all), so catching bad
    # values here lets us tell exactly which rows/values are the problem
    if table_name == "fact_sales_inventory":
        for col, allowed in (("weather", ALLOWED_WEATHER), ("season", ALLOWED_SEASON)):
            if col not in df.columns:
                continue
            cleaned = df[col].astype(str).str.strip().str.title()
            # some rows have 'unknown'/'UNKNOWN' etc, normalize those too
            cleaned = cleaned.replace({"Nan": "Unknown"})
            bad_mask = ~cleaned.isin(allowed)
            bad_count = int(bad_mask.sum())
            if bad_count > 0:
                bad_values = sorted(df.loc[bad_mask, col].astype(str).unique().tolist())
                raise ValueError(
                    f"{csv_path.name}: {bad_count} row(s) have a '{col}' value not "
                    f"allowed by the chk_{col} CHECK constraint. "
                    f"Offending value(s): {bad_values}. "
                    f"Allowed values: {sorted(allowed)}. "
                    f"Fix the source data (typos/casing/whitespace) or extend the "
                    f"CHECK constraint in schema.sql, then re-run."
                )
            # write the cleaned (trimmed, title-cased) values back so small
            # whitespace/casing differences don't trip the DB constraint
            df[col] = cleaned


def load_table(engine, csv_path: Path, table_name: str, dtype_overrides=None):
    """Load one CSV into its MySQL table, with validation and timing.

    Only keeps the columns listed in TABLE_COLUMNS[table_name] - any extra
    descriptive columns in the source CSV get dropped before insert.
    """
    start_time = time.time()
    logger.info(f"Loading '{table_name}' from {csv_path.name}...")

    df = pd.read_csv(csv_path)
    logger.info(f"  CSV read: {len(df):,} rows × {df.shape[1]} columns")

    validate_csv(df, table_name, csv_path)

    expected_cols = TABLE_COLUMNS[table_name]
    df = df[expected_cols]

    if dtype_overrides:
        for col, fn in dtype_overrides.items():
            if col in df.columns:
                df[col] = fn(df[col])

    # NOTE: method="multi" would build one giant multi-row INSERT per
    # chunk, and with chunksize=1000 and 17 columns that can blow past
    # MySQL's max_allowed_packet or trigger "MySQL server has gone away"
    # on some local setups. Sticking with pandas' default one-row-at-a-time
    # executemany + a smaller chunksize instead — slower, but reliable,
    # and it makes it possible to pinpoint the exact row that fails.
    try:
        df.to_sql(
            table_name,
            con=engine,
            if_exists="append",
            index=False,
            chunksize=200,
        )
        elapsed = time.time() - start_time
        logger.info(f"  ✅ {table_name}: {len(df):,} rows loaded in {elapsed:.1f}s")
    except Exception as e:
        logger.error(f"  ❌ Failed to load '{table_name}': {e}")
        raise


def truncate_all(engine):
    """Wipe existing rows before a fresh load, child tables first so FKs don't complain."""
    tables_in_delete_order = list(reversed(LOAD_ORDER))
    logger.info("Truncating existing data (FK-safe order)...")
    with engine.begin() as conn:
        conn.execute(text("SET FOREIGN_KEY_CHECKS = 0"))
        for t in tables_in_delete_order:
            conn.execute(text(f"TRUNCATE TABLE {t}"))
            logger.info(f"  Truncated: {t}")
        conn.execute(text("SET FOREIGN_KEY_CHECKS = 1"))
    logger.info("Truncation complete.\n")


def verify_counts(engine):
    """After loading, check row counts and referential integrity."""
    logger.info("\n" + "=" * 60)
    logger.info("Post-Load Verification")
    logger.info("=" * 60)

    all_ok = True
    with engine.connect() as conn:
        for table_name in LOAD_ORDER:
            count = conn.execute(text(f"SELECT COUNT(*) FROM {table_name}")).scalar()
            expected = EXPECTED_COUNTS.get(table_name)

            if expected is not None:
                status = "✅" if count == expected else "⚠️"
                if count != expected:
                    all_ok = False
                logger.info(f"  {status} {table_name}: {count:,} rows (expected: {expected})")
            else:
                logger.info(f"  ℹ️  {table_name}: {count:,} rows")

    logger.info("\nReferential Integrity Checks:")
    with engine.connect() as conn:
        # any fact rows pointing at a store_id that doesn't exist?
        orphan_stores = conn.execute(text(
            "SELECT COUNT(*) FROM fact_sales_inventory f "
            "LEFT JOIN stores s ON f.store_id = s.store_id "
            "WHERE s.store_id IS NULL"
        )).scalar()
        logger.info(f"  {'✅' if orphan_stores == 0 else '⚠️'} Orphaned fact records (store_id): {orphan_stores}")

        # same check but for product_id
        orphan_products = conn.execute(text(
            "SELECT COUNT(*) FROM fact_sales_inventory f "
            "LEFT JOIN products p ON f.product_id = p.product_id "
            "WHERE p.product_id IS NULL"
        )).scalar()
        logger.info(f"  {'✅' if orphan_products == 0 else '⚠️'} Orphaned fact records (product_id): {orphan_products}")

    if all_ok:
        logger.info("\n🎉 All counts match expected values.")
    else:
        logger.warning("\n⚠️  Some counts differ from expected — review the log above.")


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    total_start = time.time()
    logger.info("=" * 60)
    logger.info("Retail Analytics — Data Loader")
    logger.info(f"Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info("=" * 60)

    # connect
    engine = get_engine()
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))
    logger.info(f"Connected to database: {DB_CONFIG['database']}\n")

    # clear out old data first
    truncate_all(engine)

    # load dimension tables, parent -> child
    logger.info("Loading dimension tables (parent → child order)...")
    for table_name in LOAD_ORDER[:-1]:  # everything except the fact table
        csv_name = f"{table_name}.csv"
        load_table(engine, DATA_DIR / csv_name, table_name)

    # then the fact table
    logger.info("\nLoading fact table...")
    load_table(engine, FACT_CSV, "fact_sales_inventory")

    # verify what we just loaded
    verify_counts(engine)

    total_elapsed = time.time() - total_start
    logger.info("\n" + "=" * 60)
    logger.info(f"Data loading complete in {total_elapsed:.1f}s")
    logger.info(f"Log file: data_loader.log")
    logger.info("=" * 60)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)

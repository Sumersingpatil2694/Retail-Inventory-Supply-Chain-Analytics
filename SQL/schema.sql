-- Retail Inventory & Supply Chain Performance Analytics
-- Phase 1: Database Schema (MySQL 8.0+)
-- Author: Sumersing Patil
--
-- What's in here on top of a bare-bones schema:
--   - NOT NULL on all the columns that actually matter
--   - DEFAULT values for the flag columns
--   - composite indexes for the query patterns I actually use
--   - CHECK constraints so bad numeric ranges get rejected at insert time
--   - ON DELETE CASCADE-ish behavior on the fact table FKs
--   - comments on every table/column so future me remembers what's what

CREATE DATABASE IF NOT EXISTS retail_analytics
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE retail_analytics;

-- drop in reverse dependency order so this script can be re-run safely
DROP TABLE IF EXISTS fact_sales_inventory;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS suppliers;
DROP TABLE IF EXISTS stores;
DROP TABLE IF EXISTS warehouses;

-- ---------------------------------------------------------------------------
-- 1. WAREHOUSES (top-level dimension, nothing depends on it)
-- ---------------------------------------------------------------------------
CREATE TABLE warehouses (
    warehouse_id    VARCHAR(10)  PRIMARY KEY,
    warehouse_name  VARCHAR(100) NOT NULL,
    city            VARCHAR(50)  NOT NULL,
    capacity_units  INT          NOT NULL CHECK (capacity_units > 0),
    created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_wh_city (city)
) ENGINE=InnoDB
  COMMENT='Warehouse master dimension — regional distribution centers';

-- ---------------------------------------------------------------------------
-- 2. STORES  (FK -> warehouses)
-- ---------------------------------------------------------------------------
CREATE TABLE stores (
    store_id        VARCHAR(10)  PRIMARY KEY,
    store_name      VARCHAR(100) NOT NULL,
    city            VARCHAR(50)  NOT NULL,
    warehouse_id    VARCHAR(10)  NOT NULL,
    store_type      VARCHAR(20),
    created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    INDEX idx_store_city (city),
    INDEX idx_store_type (store_type)
) ENGINE=InnoDB
  COMMENT='Retail store master dimension — 25 stores across India';

-- ---------------------------------------------------------------------------
-- 3. SUPPLIERS
-- ---------------------------------------------------------------------------
CREATE TABLE suppliers (
    supplier_id        VARCHAR(10)  PRIMARY KEY,
    supplier_name      VARCHAR(100) NOT NULL,
    city               VARCHAR(50)  NOT NULL,
    avg_lead_time_days INT          NOT NULL CHECK (avg_lead_time_days >= 0),
    reliability_score  INT          NOT NULL CHECK (reliability_score BETWEEN 0 AND 100),
    created_at         TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_supplier_city (city)
) ENGINE=InnoDB
  COMMENT='Supplier master dimension — 20 domestic + international suppliers';

-- ---------------------------------------------------------------------------
-- 4. PRODUCTS  (FK -> suppliers)
-- ---------------------------------------------------------------------------
CREATE TABLE products (
    product_id    VARCHAR(15)   PRIMARY KEY,
    product_name  VARCHAR(100)  NOT NULL,
    category      VARCHAR(50)   NOT NULL,
    supplier_id   VARCHAR(10)   NOT NULL,
    unit_cost     DECIMAL(10,2) NOT NULL CHECK (unit_cost >= 0),
    unit_price    DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    reorder_point INT           NOT NULL CHECK (reorder_point >= 0),
    created_at    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    INDEX idx_product_category (category),
    INDEX idx_product_supplier (supplier_id)
) ENGINE=InnoDB
  COMMENT='Product master dimension — 410 products across 6 categories';

-- ---------------------------------------------------------------------------
-- 5. FACT TABLE  (child of all four dimension tables)
--    Heads up: the raw source file also has a few extra columns
--    (festival_season_flag, back_to_school_flag, promo_type,
--    customer_segment, returned_units, refund_amount, return_reason).
--    Left them out on purpose to keep this table in sync with
--    fact_sales_inventory_CLEANED.csv (section 4 of the notebook) —
--    they're still available for the Python/Excel/Tableau side via
--    fact_sales_inventory_analytics.csv if needed.
-- ---------------------------------------------------------------------------
CREATE TABLE fact_sales_inventory (
    id                   INT AUTO_INCREMENT PRIMARY KEY,
    date                 DATE          NOT NULL,
    store_id             VARCHAR(10)   NOT NULL,
    product_id           VARCHAR(15)   NOT NULL,
    warehouse_id         VARCHAR(10)   NOT NULL,
    supplier_id          VARCHAR(10)   NOT NULL,
    units_sold           INT           NOT NULL CHECK (units_sold >= 0),
    inventory_level      INT           NOT NULL CHECK (inventory_level >= 0),
    units_ordered        INT           NOT NULL DEFAULT 0 CHECK (units_ordered >= 0),
    units_received       INT           NOT NULL DEFAULT 0 CHECK (units_received >= 0),
    delivery_delay_days  INT           NOT NULL DEFAULT 0 CHECK (delivery_delay_days >= 0),
    stockout_flag        TINYINT       NOT NULL DEFAULT 0 CHECK (stockout_flag IN (0, 1)),
    revenue              DECIMAL(12,2) NOT NULL CHECK (revenue >= 0),
    unit_price_txn       DECIMAL(10,2) NOT NULL CHECK (unit_price_txn >= 0),
    discount_pct         DECIMAL(5,2)  NOT NULL DEFAULT 0.00 CHECK (discount_pct BETWEEN 0 AND 100),
    holiday_promo_flag   TINYINT       NOT NULL DEFAULT 0 CHECK (holiday_promo_flag IN (0, 1)),
    weather              VARCHAR(20)   NOT NULL DEFAULT 'Unknown',
    season               VARCHAR(20)   NOT NULL,
    created_at           TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (store_id)     REFERENCES stores(store_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (product_id)   REFERENCES products(product_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (supplier_id)  REFERENCES suppliers(supplier_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,

    CONSTRAINT chk_weather CHECK (weather IN ('Sunny','Rain','Cloudy','Cold','Heatwave','Storm','Unknown')),
    CONSTRAINT chk_season  CHECK (season  IN ('Winter','Summer','Autumn','Monsoon'))
) ENGINE=InnoDB
  COMMENT='Daily store-product level sales & inventory fact table (~48,973 rows post-cleaning)';

-- ---------------------------------------------------------------------------
-- indexes on the columns I actually filter by a lot
-- ---------------------------------------------------------------------------
CREATE INDEX idx_fact_date        ON fact_sales_inventory(date);
CREATE INDEX idx_fact_store       ON fact_sales_inventory(store_id);
CREATE INDEX idx_fact_product     ON fact_sales_inventory(product_id);
CREATE INDEX idx_fact_warehouse   ON fact_sales_inventory(warehouse_id);
CREATE INDEX idx_fact_supplier    ON fact_sales_inventory(supplier_id);
CREATE INDEX idx_fact_season      ON fact_sales_inventory(season);
CREATE INDEX idx_fact_stockout    ON fact_sales_inventory(stockout_flag);

-- composite index for the date + store combo, since that's the most common filter
CREATE INDEX idx_fact_date_store  ON fact_sales_inventory(date, store_id);

-- stops the same product/store/date getting imported twice
-- (belt-and-suspenders on top of the drop_duplicates() step in Python)
ALTER TABLE fact_sales_inventory
    ADD CONSTRAINT uq_fact_date_store_product UNIQUE (date, store_id, product_id);

-- ---------------------------------------------------------------------------
-- quick sanity checks, run these manually after loading data
-- ---------------------------------------------------------------------------
-- SELECT COUNT(*) AS warehouses_ct FROM warehouses;          -- expected 8
-- SELECT COUNT(*) AS stores_ct     FROM stores;              -- expected 25
-- SELECT COUNT(*) AS suppliers_ct  FROM suppliers;           -- expected 20
-- SELECT COUNT(*) AS products_ct   FROM products;            -- expected 410
-- SELECT COUNT(*) AS fact_ct       FROM fact_sales_inventory; -- expected ~48,973

-- ---------------------------------------------------------------------------
-- referential integrity check, also manual, also after loading data
-- ---------------------------------------------------------------------------
-- SELECT 'orphan_fact_store' AS check_name,
--        COUNT(*) AS orphan_count
-- FROM fact_sales_inventory f
-- LEFT JOIN stores s ON f.store_id = s.store_id
-- WHERE s.store_id IS NULL;

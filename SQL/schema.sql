-- ============================================================================
-- Retail Inventory & Supply Chain Performance Analytics
-- Phase 1: Database Schema (MySQL)
-- Author: Sumersing Patil
-- ============================================================================

CREATE DATABASE IF NOT EXISTS retail_analytics;
USE retail_analytics;

-- Drop tables in reverse dependency order (safe re-run)
DROP TABLE IF EXISTS fact_sales_inventory;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS suppliers;
DROP TABLE IF EXISTS stores;
DROP TABLE IF EXISTS warehouses;

-- ---------------------------------------------------------------------------
-- 1. WAREHOUSES (parent)
-- ---------------------------------------------------------------------------
CREATE TABLE warehouses (
    warehouse_id   VARCHAR(10) PRIMARY KEY,
    warehouse_name VARCHAR(100),
    city           VARCHAR(50),
    capacity_units INT,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------------
-- 2. STORES  (FK -> warehouses)
-- ---------------------------------------------------------------------------
CREATE TABLE stores (
    store_id     VARCHAR(10) PRIMARY KEY,
    store_name   VARCHAR(100),
    city         VARCHAR(50),
    warehouse_id VARCHAR(10),
    store_type   VARCHAR(20),
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id)
);

-- ---------------------------------------------------------------------------
-- 3. SUPPLIERS
-- ---------------------------------------------------------------------------
CREATE TABLE suppliers (
    supplier_id        VARCHAR(10) PRIMARY KEY,
    supplier_name      VARCHAR(100),
    city               VARCHAR(50),
    avg_lead_time_days INT,
    reliability_score  INT,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_reliability_score CHECK (reliability_score BETWEEN 0 AND 100)
);

-- ---------------------------------------------------------------------------
-- 4. PRODUCTS  (FK -> suppliers)
-- ---------------------------------------------------------------------------
CREATE TABLE products (
    product_id    VARCHAR(15) PRIMARY KEY,
    product_name  VARCHAR(100),
    category      VARCHAR(50),
    supplier_id   VARCHAR(10),
    unit_cost     DECIMAL(10,2),
    unit_price    DECIMAL(10,2),
    reorder_point INT,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id)
);

-- ---------------------------------------------------------------------------
-- 5. FACT TABLE  (child of all four dimensions)
-- ---------------------------------------------------------------------------
CREATE TABLE fact_sales_inventory (
    id                   INT AUTO_INCREMENT PRIMARY KEY,
    date                 DATE,
    store_id             VARCHAR(10),
    product_id           VARCHAR(15),
    warehouse_id         VARCHAR(10),
    supplier_id          VARCHAR(10),
    units_sold           INT,
    inventory_level      INT,
    units_ordered        INT,
    units_received       INT,
    delivery_delay_days  INT,
    stockout_flag        TINYINT,
    revenue              DECIMAL(12,2),
    unit_price_txn       DECIMAL(10,2),
    discount_pct         DECIMAL(5,2),
    holiday_promo_flag   TINYINT,
    weather              VARCHAR(20),
    season               VARCHAR(20),
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (store_id)     REFERENCES stores(store_id),
    FOREIGN KEY (product_id)   REFERENCES products(product_id),
    FOREIGN KEY (warehouse_id) REFERENCES warehouses(warehouse_id),
    FOREIGN KEY (supplier_id)  REFERENCES suppliers(supplier_id),
    CONSTRAINT chk_weather CHECK (weather IN ('Sunny','Rainy','Cloudy','Snowy')),
    CONSTRAINT chk_season  CHECK (season  IN ('Winter','Summer','Autumn','Spring'))
);

-- ---------------------------------------------------------------------------
-- Performance indices on high-cardinality filter columns
-- ---------------------------------------------------------------------------
CREATE INDEX idx_fact_date        ON fact_sales_inventory(date);
CREATE INDEX idx_fact_store       ON fact_sales_inventory(store_id);
CREATE INDEX idx_fact_product     ON fact_sales_inventory(product_id);
CREATE INDEX idx_fact_warehouse   ON fact_sales_inventory(warehouse_id);
CREATE INDEX idx_fact_supplier    ON fact_sales_inventory(supplier_id);

-- Prevents duplicate rows for the same product/store/date being imported
-- twice (safety net on top of the Python drop_duplicates() step)
ALTER TABLE fact_sales_inventory
    ADD CONSTRAINT uq_fact_date_store_product UNIQUE (date, store_id, product_id);

-- ---------------------------------------------------------------------------
-- Sanity checks (run after imports)
-- ---------------------------------------------------------------------------
-- SELECT COUNT(*) AS warehouses_ct FROM warehouses;   -- expected 3
-- SELECT COUNT(*) AS stores_ct     FROM stores;       -- expected 5
-- SELECT COUNT(*) AS suppliers_ct  FROM suppliers;    -- expected 8
-- SELECT COUNT(*) AS products_ct   FROM products;     -- expected 100
-- SELECT COUNT(*) AS fact_ct       FROM fact_sales_inventory;

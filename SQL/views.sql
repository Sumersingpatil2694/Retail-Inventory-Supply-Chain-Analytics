-- ============================================================================
-- Retail Inventory & Supply Chain Performance Analytics
-- Phase 3: 8 Analytical Views
-- Author: Sumersing Patil
-- ============================================================================
USE retail_analytics;

-- Drop existing views (safe re-run)
DROP VIEW IF EXISTS vw_monthly_kpi_summary;
DROP VIEW IF EXISTS vw_reorder_recommendation;
DROP VIEW IF EXISTS vw_warehouse_performance;
DROP VIEW IF EXISTS vw_regional_performance;
DROP VIEW IF EXISTS vw_supplier_performance;
DROP VIEW IF EXISTS vw_stockout_overstock;
DROP VIEW IF EXISTS vw_dead_stock;
DROP VIEW IF EXISTS vw_inventory_turnover;

-- ---------------------------------------------------------------------------
-- 1. INVENTORY TURNOVER ANALYSIS
--    Turnover = total units sold / average inventory on hand
-- ---------------------------------------------------------------------------
CREATE VIEW vw_inventory_turnover AS
SELECT
    p.product_id,
    p.product_name,
    p.category,
    SUM(f.units_sold)                                            AS total_units_sold,
    ROUND(AVG(f.inventory_level), 2)                             AS avg_inventory,
    ROUND(SUM(f.units_sold) / NULLIF(AVG(f.inventory_level), 0), 2) AS turnover_ratio
FROM fact_sales_inventory f
JOIN products p ON f.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.category;

-- ---------------------------------------------------------------------------
-- 2. DEAD STOCK
--    Threshold: turnover_ratio < 0.5 (i.e. average inventory on hand sells
--    through less than half a time over the period). This is a common
--    retail "slow mover" heuristic used because a ratio below 0.5 means
--    a product spends more time sitting in stock than moving off the shelf
--    -> capital is effectively stuck. Chosen as the midpoint cutoff since
--    no company-specific target turnover was provided in the source data;
--    adjust to an actual category-level target turnover if one becomes
--    available.
-- ---------------------------------------------------------------------------
CREATE VIEW vw_dead_stock AS
SELECT *
FROM vw_inventory_turnover
WHERE turnover_ratio < 0.5
ORDER BY turnover_ratio ASC;

-- ---------------------------------------------------------------------------
-- 3. STOCKOUT & OVERSTOCK  (per product-store combination)
--    Overstock day = inventory_level represents 30+ days of supply at that
--    product-store's own average daily sales rate ("days of supply" heuristic
--    — standard retail proxy for excess inventory when no explicit max-stock
--    capacity column exists in the source data). 30 days is used because it
--    matches a standard monthly replenishment cycle: holding more than a
--    month's worth of demand as inventory is a widely-used industry rule of
--    thumb for flagging excess stock. Recalibrate against actual warehouse
--    capacity_units or a company-specific replenishment cycle if available.
-- ---------------------------------------------------------------------------
CREATE VIEW vw_stockout_overstock AS
WITH product_store_rate AS (
    SELECT product_id, store_id,
           AVG(units_sold) AS avg_daily_sales
    FROM fact_sales_inventory
    GROUP BY product_id, store_id
)
SELECT
    f.product_id,
    p.product_name,
    f.store_id,
    SUM(f.stockout_flag)                                       AS stockout_days,
    SUM(CASE WHEN f.inventory_level > 30 * NULLIF(r.avg_daily_sales, 0)
             THEN 1 ELSE 0 END)                                AS overstock_days,
    COUNT(*)                                                   AS total_days,
    ROUND(SUM(f.stockout_flag) * 100.0 / COUNT(*), 2)          AS stockout_rate_pct,
    ROUND(SUM(CASE WHEN f.inventory_level > 30 * NULLIF(r.avg_daily_sales, 0)
                   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)   AS overstock_rate_pct,
    ROUND(AVG(f.inventory_level), 2)                           AS avg_inventory
FROM fact_sales_inventory f
JOIN products p ON f.product_id = p.product_id
JOIN product_store_rate r ON f.product_id = r.product_id AND f.store_id = r.store_id
GROUP BY f.product_id, p.product_name, f.store_id;

-- ---------------------------------------------------------------------------
-- 4. SUPPLIER PERFORMANCE SCORECARD
--    On-time delivery threshold: delivery_delay_days <= 2. Chosen as the
--    cutoff because the fastest supplier in this dataset (Summit Supply
--    Chain, ~3.4 day average delay) already runs above 2 days, so a <=2 day
--    bar treats "on-time" as a genuinely tight standard rather than an
--    average that most deliveries would trivially pass. Adjust to match an
--    actual SLA if suppliers are contractually bound to a different window.
-- ---------------------------------------------------------------------------
CREATE VIEW vw_supplier_performance AS
SELECT
    s.supplier_id,
    s.supplier_name,
    s.avg_lead_time_days,
    s.reliability_score,
    ROUND(AVG(f.delivery_delay_days), 2)                                     AS actual_avg_delay,
    ROUND(SUM(CASE WHEN f.delivery_delay_days <= 2 THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                                             AS on_time_delivery_pct,
    ROUND(SUM(f.units_received) * 100.0 / NULLIF(SUM(f.units_ordered), 0), 2) AS fill_rate_pct
FROM fact_sales_inventory f
JOIN suppliers s ON f.supplier_id = s.supplier_id
GROUP BY s.supplier_id, s.supplier_name, s.avg_lead_time_days, s.reliability_score;

-- ---------------------------------------------------------------------------
-- 5. REGIONAL SALES PERFORMANCE  (uses window RANK)
-- ---------------------------------------------------------------------------
CREATE VIEW vw_regional_performance AS
SELECT
    st.city,
    ROUND(SUM(f.revenue), 2)                            AS total_revenue,
    RANK() OVER (ORDER BY SUM(f.revenue) DESC)          AS revenue_rank
FROM fact_sales_inventory f
JOIN stores st ON f.store_id = st.store_id
GROUP BY st.city;

-- ---------------------------------------------------------------------------
-- 6. WAREHOUSE PERFORMANCE
-- ---------------------------------------------------------------------------
CREATE VIEW vw_warehouse_performance AS
SELECT
    w.warehouse_id,
    w.warehouse_name,
    ROUND(AVG(f.inventory_level), 2) AS avg_inventory,
    SUM(f.stockout_flag)             AS total_stockouts,
    ROUND(AVG(f.delivery_delay_days), 2) AS avg_delay
FROM fact_sales_inventory f
JOIN warehouses w ON f.warehouse_id = w.warehouse_id
GROUP BY w.warehouse_id, w.warehouse_name;

-- ---------------------------------------------------------------------------
-- 7. REORDER RECOMMENDATION  (latest inventory vs reorder point, CTE + window)
-- ---------------------------------------------------------------------------
CREATE VIEW vw_reorder_recommendation AS
WITH latest_inventory AS (
    SELECT
        id,
        product_id,
        store_id,
        inventory_level,
        date,
        ROW_NUMBER() OVER (PARTITION BY product_id, store_id ORDER BY date DESC, id DESC) AS rn
    FROM fact_sales_inventory
)
SELECT
    li.product_id,
    p.product_name,
    li.store_id,
    li.inventory_level,
    p.reorder_point,
    CASE WHEN li.inventory_level <= p.reorder_point
         THEN 'Reorder Now' ELSE 'OK' END AS reorder_status
FROM latest_inventory li
JOIN products p ON li.product_id = p.product_id
WHERE li.rn = 1;

-- ---------------------------------------------------------------------------
-- 8. MONTHLY BUSINESS KPI SUMMARY
-- ---------------------------------------------------------------------------
CREATE VIEW vw_monthly_kpi_summary AS
SELECT
    DATE_FORMAT(date, '%Y-%m')                                  AS month,
    ROUND(SUM(revenue), 2)                                      AS total_revenue,
    SUM(units_sold)                                             AS total_units_sold,
    ROUND(SUM(stockout_flag) * 100.0 / COUNT(*), 2)             AS stockout_rate_pct
FROM fact_sales_inventory
GROUP BY DATE_FORMAT(date, '%Y-%m')
ORDER BY month;

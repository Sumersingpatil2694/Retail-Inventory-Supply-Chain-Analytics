-- Retail Inventory & Supply Chain Performance Analytics
-- Phase 3: 12 Analytical Views (started with 8, added 4 more)
-- Author: Sumersing Patil
--
-- What's new vs the first version:
--   - 4 new views: ABC Classification, Store Ranking, Category KPI,
--     Quarterly Growth
--   - COALESCE added wherever a NULL could sneak through
--   - RANK/DENSE_RANK/ROW_NUMBER/LAG window functions used throughout
--   - percentage-of-total calcs added where useful

USE retail_analytics;

-- drop existing views first so this file can be re-run safely
DROP VIEW IF EXISTS vw_quarterly_growth;
DROP VIEW IF EXISTS vw_category_kpi;
DROP VIEW IF EXISTS vw_store_ranking;
DROP VIEW IF EXISTS vw_abc_classification;
DROP VIEW IF EXISTS vw_monthly_kpi_summary;
DROP VIEW IF EXISTS vw_reorder_recommendation;
DROP VIEW IF EXISTS vw_warehouse_performance;
DROP VIEW IF EXISTS vw_regional_performance;
DROP VIEW IF EXISTS vw_supplier_performance;
DROP VIEW IF EXISTS vw_stockout_overstock;
DROP VIEW IF EXISTS vw_dead_stock;
DROP VIEW IF EXISTS vw_inventory_turnover;

-- ---------------------------------------------------------------------------
-- 1. INVENTORY TURNOVER
--    turnover = total units sold / average inventory on hand
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
--    anything under 0.5 turnover is basically capital sitting on a shelf
-- ---------------------------------------------------------------------------
CREATE VIEW vw_dead_stock AS
SELECT *
FROM vw_inventory_turnover
WHERE turnover_ratio < 0.5
ORDER BY turnover_ratio ASC;

-- ---------------------------------------------------------------------------
-- 3. STOCKOUT & OVERSTOCK  (per product-store combo)
--    calling it an "overstock day" when inventory > 30 days of supply
--    at that product/store's average daily sales
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
--    counting delivery on-time if delay is 2 days or less
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
    ROUND(SUM(f.units_received) * 100.0 / NULLIF(SUM(f.units_ordered), 0), 2) AS fill_rate_pct,
    ROUND(SUM(f.revenue), 2)                                                 AS total_revenue,
    COUNT(*)                                                                 AS total_transactions,
    RANK() OVER (ORDER BY AVG(f.delivery_delay_days) ASC)                    AS delay_rank
FROM fact_sales_inventory f
JOIN suppliers s ON f.supplier_id = s.supplier_id
GROUP BY s.supplier_id, s.supplier_name, s.avg_lead_time_days, s.reliability_score;

-- ---------------------------------------------------------------------------
-- 5. REGIONAL SALES PERFORMANCE  (city-level, ranked by revenue)
-- ---------------------------------------------------------------------------
CREATE VIEW vw_regional_performance AS
SELECT
    st.city,
    ROUND(SUM(f.revenue), 2)                            AS total_revenue,
    SUM(f.units_sold)                                   AS total_units_sold,
    ROUND(AVG(f.stockout_flag) * 100, 2)                AS stockout_rate_pct,
    RANK() OVER (ORDER BY SUM(f.revenue) DESC)          AS revenue_rank
FROM fact_sales_inventory f
JOIN stores st ON f.store_id = st.store_id
GROUP BY st.city;

-- ---------------------------------------------------------------------------
-- 6. WAREHOUSE PERFORMANCE
--    LEFT JOIN so warehouses with zero activity still show up
-- ---------------------------------------------------------------------------
CREATE VIEW vw_warehouse_performance AS
SELECT
    w.warehouse_id,
    w.warehouse_name,
    w.capacity_units,
    ROUND(AVG(f.inventory_level), 2)                       AS avg_inventory,
    COALESCE(SUM(f.stockout_flag), 0)                      AS total_stockouts,
    COALESCE(ROUND(AVG(f.delivery_delay_days), 2), 0)      AS avg_delay,
    COALESCE(ROUND(SUM(f.revenue), 2), 0)                  AS total_revenue,
    ROUND(COALESCE(AVG(f.inventory_level), 0) / w.capacity_units * 100, 2) AS utilization_pct
FROM warehouses w
LEFT JOIN fact_sales_inventory f ON f.warehouse_id = w.warehouse_id
GROUP BY w.warehouse_id, w.warehouse_name, w.capacity_units;

-- ---------------------------------------------------------------------------
-- 7. REORDER RECOMMENDATION
--    grabs the latest inventory reading per product/store, then compares
--    against reorder_point
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
    p.category,
    li.store_id,
    li.inventory_level,
    p.reorder_point,
    (p.reorder_point - li.inventory_level)                AS gap_to_reorder,
    CASE WHEN li.inventory_level <= p.reorder_point
         THEN 'Reorder Now' ELSE 'OK' END                  AS reorder_status,
    CASE
        WHEN li.inventory_level <= p.reorder_point * 0.5 THEN 'Critical'
        WHEN li.inventory_level <= p.reorder_point        THEN 'High'
        ELSE 'OK'
    END                                                    AS urgency_level
FROM latest_inventory li
JOIN products p ON li.product_id = p.product_id
WHERE li.rn = 1;

-- ---------------------------------------------------------------------------
-- 8. MONTHLY BUSINESS KPI SUMMARY  (added fill rate + avg discount here)
-- ---------------------------------------------------------------------------
CREATE VIEW vw_monthly_kpi_summary AS
SELECT
    DATE_FORMAT(date, '%Y-%m')                                  AS month,
    ROUND(SUM(revenue), 2)                                      AS total_revenue,
    SUM(units_sold)                                             AS total_units_sold,
    ROUND(SUM(stockout_flag) * 100.0 / COUNT(*), 2)             AS stockout_rate_pct,
    ROUND(SUM(units_received) * 100.0 / NULLIF(SUM(units_ordered), 0), 2) AS fill_rate_pct,
    ROUND(AVG(discount_pct), 2)                                 AS avg_discount_pct
FROM fact_sales_inventory
GROUP BY DATE_FORMAT(date, '%Y-%m')
ORDER BY month;

-- ---------------------------------------------------------------------------
-- 9. ABC CLASSIFICATION  (classic Pareto / 80-20 split) — new
--    A: cumulative revenue up to 80%
--    B: 80–95%
--    C: everything past 95%
-- ---------------------------------------------------------------------------
CREATE VIEW vw_abc_classification AS
WITH product_revenue AS (
    SELECT
        p.product_id,
        p.product_name,
        p.category,
        SUM(f.revenue) AS total_revenue
    FROM fact_sales_inventory f
    JOIN products p ON f.product_id = p.product_id
    GROUP BY p.product_id, p.product_name, p.category
),
cumulative AS (
    SELECT
        product_id,
        product_name,
        category,
        total_revenue,
        SUM(total_revenue) OVER (ORDER BY total_revenue DESC) AS cumulative_revenue,
        SUM(total_revenue) OVER ()                            AS grand_total
    FROM product_revenue
)
SELECT
    product_id,
    product_name,
    category,
    ROUND(total_revenue, 2) AS total_revenue,
    ROUND(cumulative_revenue / grand_total * 100, 2) AS cumulative_pct,
    CASE
        WHEN cumulative_revenue / grand_total * 100 <= 80 THEN 'A'
        WHEN cumulative_revenue / grand_total * 100 <= 95 THEN 'B'
        ELSE 'C'
    END AS abc_class
FROM cumulative
ORDER BY total_revenue DESC;

-- ---------------------------------------------------------------------------
-- 10. STORE RANKING  (revenue + stockout, side by side) — new
-- ---------------------------------------------------------------------------
CREATE VIEW vw_store_ranking AS
SELECT
    st.store_id,
    st.store_name,
    st.city,
    st.store_type,
    ROUND(SUM(f.revenue), 2)                       AS total_revenue,
    SUM(f.units_sold)                              AS total_units_sold,
    ROUND(SUM(f.stockout_flag) * 100.0 / COUNT(*), 2) AS stockout_rate_pct,
    ROUND(AVG(f.inventory_level), 2)               AS avg_inventory,
    RANK() OVER (ORDER BY SUM(f.revenue) DESC)     AS revenue_rank,
    RANK() OVER (ORDER BY SUM(f.stockout_flag) * 100.0 / COUNT(*) DESC) AS stockout_rank
FROM fact_sales_inventory f
JOIN stores st ON f.store_id = st.store_id
GROUP BY st.store_id, st.store_name, st.city, st.store_type;

-- ---------------------------------------------------------------------------
-- 11. CATEGORY KPI SUMMARY — new
-- ---------------------------------------------------------------------------
CREATE VIEW vw_category_kpi AS
SELECT
    p.category,
    COUNT(DISTINCT p.product_id)                                    AS product_count,
    ROUND(SUM(f.revenue), 2)                                        AS total_revenue,
    SUM(f.units_sold)                                               AS total_units_sold,
    ROUND(SUM(f.revenue) / NULLIF(SUM(f.units_sold), 0), 2)         AS avg_selling_price,
    ROUND(SUM(f.stockout_flag) * 100.0 / COUNT(*), 2)               AS stockout_rate_pct,
    ROUND(AVG(f.inventory_level), 2)                                AS avg_inventory,
    ROUND(SUM(f.revenue) * 100.0 / SUM(SUM(f.revenue)) OVER (), 2)  AS revenue_contribution_pct
FROM fact_sales_inventory f
JOIN products p ON f.product_id = p.product_id
GROUP BY p.category
ORDER BY total_revenue DESC;

-- ---------------------------------------------------------------------------
-- 12. QUARTERLY GROWTH  (QoQ + YoY via LAG) — new
-- ---------------------------------------------------------------------------
CREATE VIEW vw_quarterly_growth AS
WITH quarterly AS (
    SELECT
        YEAR(date)                                                       AS yr,
        QUARTER(date)                                                    AS qtr,
        ROUND(SUM(revenue), 2)                                           AS quarter_revenue,
        SUM(units_sold)                                                  AS quarter_units
    FROM fact_sales_inventory
    GROUP BY YEAR(date), QUARTER(date)
)
SELECT
    yr,
    qtr,
    quarter_revenue,
    quarter_units,
    -- quarter vs previous quarter
    ROUND(
        (quarter_revenue - LAG(quarter_revenue) OVER (ORDER BY yr, qtr))
        / NULLIF(LAG(quarter_revenue) OVER (ORDER BY yr, qtr), 0) * 100, 2
    ) AS qoq_growth_pct,
    -- same quarter, one year back
    ROUND(
        (quarter_revenue - LAG(quarter_revenue, 4) OVER (ORDER BY yr, qtr))
        / NULLIF(LAG(quarter_revenue, 4) OVER (ORDER BY yr, qtr), 0) * 100, 2
    ) AS yoy_growth_pct
FROM quarterly
ORDER BY yr, qtr;

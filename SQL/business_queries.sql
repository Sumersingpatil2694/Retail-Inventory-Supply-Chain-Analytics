-- ============================================================================
-- Ad-hoc business queries (not views) - Sumersing Patil
-- ============================================================================
USE retail_analytics;

-- Q1. Top 5 slow-moving products (lowest turnover)
SELECT product_id, product_name, category, turnover_ratio
FROM vw_inventory_turnover
ORDER BY turnover_ratio ASC
LIMIT 5;

-- Q2. Worst-performing supplier by delay AND fill rate
SELECT supplier_id, supplier_name, actual_avg_delay,
       on_time_delivery_pct, fill_rate_pct
FROM vw_supplier_performance
ORDER BY actual_avg_delay DESC, fill_rate_pct ASC
LIMIT 1;

-- Q3. Top 10 revenue-generating products
SELECT p.product_id, p.product_name, p.category,
       ROUND(SUM(f.revenue), 2) AS total_revenue
FROM fact_sales_inventory f
JOIN products p ON f.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_revenue DESC
LIMIT 10;

-- Q4. Products currently needing reorder (latest inventory <= reorder point)
SELECT product_id, product_name, store_id, inventory_level,
       reorder_point, reorder_status
FROM vw_reorder_recommendation
WHERE reorder_status = 'Reorder Now'
ORDER BY (reorder_point - inventory_level) DESC;

-- Q5. Revenue impact of promotional/holiday days vs normal days
SELECT holiday_promo_flag,
       COUNT(*)                    AS num_records,
       ROUND(AVG(revenue), 2)      AS avg_daily_revenue,
       ROUND(AVG(units_sold), 2)   AS avg_units_sold,
       ROUND(AVG(discount_pct), 2) AS avg_discount
FROM fact_sales_inventory
GROUP BY holiday_promo_flag;

-- Q6. Weather impact on units sold
SELECT weather,
       COUNT(*)                  AS records,
       ROUND(AVG(units_sold), 2) AS avg_units_sold,
       ROUND(SUM(revenue), 2)    AS total_revenue
FROM fact_sales_inventory
GROUP BY weather
ORDER BY avg_units_sold DESC;

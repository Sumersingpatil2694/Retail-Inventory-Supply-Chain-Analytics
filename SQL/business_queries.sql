-- Ad-hoc Business Queries (not views) — Retail Analytics
-- Author: Sumersing Patil
--
-- 20 queries covering ranking, window functions, CTEs, growth analysis,
-- ABC/XYZ classification, stockout impact, supplier scorecards etc.

USE retail_analytics;

-- ============================================================
-- BASIC ANALYTICS (Q1–Q6)
-- ============================================================

-- Q1. Top 5 slow-moving products (lowest turnover)
SELECT product_id, product_name, category, turnover_ratio
FROM vw_inventory_turnover
ORDER BY turnover_ratio ASC
LIMIT 5;

-- Q2. Worst supplier, going by delay AND fill rate together
SELECT supplier_id, supplier_name, actual_avg_delay,
       on_time_delivery_pct, fill_rate_pct, delay_rank
FROM vw_supplier_performance
ORDER BY actual_avg_delay DESC, fill_rate_pct ASC
LIMIT 1;

-- Q3. Top 10 products by revenue
SELECT p.product_id, p.product_name, p.category,
       ROUND(SUM(f.revenue), 2) AS total_revenue,
       ROUND(SUM(f.revenue) * 100.0 / SUM(SUM(f.revenue)) OVER (), 2) AS revenue_pct
FROM fact_sales_inventory f
JOIN products p ON f.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY total_revenue DESC
LIMIT 10;

-- Q4. Products that need reordering right now (inventory <= reorder point)
SELECT product_id, product_name, category, store_id,
       inventory_level, reorder_point, gap_to_reorder,
       urgency_level, reorder_status
FROM vw_reorder_recommendation
WHERE reorder_status = 'Reorder Now'
ORDER BY gap_to_reorder DESC;

-- Q5. Does revenue actually go up on promo/holiday days vs normal days?
SELECT
    holiday_promo_flag,
    COUNT(*)                    AS num_records,
    ROUND(AVG(revenue), 2)      AS avg_daily_revenue,
    ROUND(AVG(units_sold), 2)   AS avg_units_sold,
    ROUND(AVG(discount_pct), 2) AS avg_discount
FROM fact_sales_inventory
GROUP BY holiday_promo_flag;

-- Q6. Does weather move units sold?
SELECT weather,
       COUNT(*)                  AS records,
       ROUND(AVG(units_sold), 2) AS avg_units_sold,
       ROUND(SUM(revenue), 2)    AS total_revenue
FROM fact_sales_inventory
GROUP BY weather
ORDER BY avg_units_sold DESC;

-- ============================================================
-- WINDOW FUNCTIONS (Q7–Q14)
-- ============================================================

-- Q7. Top 3 products per category by revenue, using ROW_NUMBER
SELECT category, product_id, product_name, total_revenue, revenue_rank
FROM (
    SELECT
        p.category,
        p.product_id,
        p.product_name,
        ROUND(SUM(f.revenue), 2) AS total_revenue,
        ROW_NUMBER() OVER (PARTITION BY p.category ORDER BY SUM(f.revenue) DESC) AS revenue_rank
    FROM fact_sales_inventory f
    JOIN products p ON f.product_id = p.product_id
    GROUP BY p.category, p.product_id, p.product_name
) ranked
WHERE revenue_rank <= 3
ORDER BY category, revenue_rank;

-- Q8. Store ranking by revenue, DENSE_RANK so ties share a rank
SELECT
    store_id,
    store_name,
    city,
    total_revenue,
    DENSE_RANK() OVER (ORDER BY total_revenue DESC) AS dense_revenue_rank
FROM vw_store_ranking
ORDER BY dense_revenue_rank
LIMIT 10;

-- Q9. Monthly revenue + running total + month-over-month growth
SELECT
    month,
    total_revenue,
    SUM(total_revenue) OVER (ORDER BY month) AS cumulative_revenue,
    ROUND(
        (total_revenue - LAG(total_revenue) OVER (ORDER BY month))
        / NULLIF(LAG(total_revenue) OVER (ORDER BY month), 0) * 100, 2
    ) AS mom_growth_pct
FROM vw_monthly_kpi_summary
ORDER BY month;

-- Q10. 3-month and 6-month moving average of revenue
SELECT
    month,
    total_revenue,
    ROUND(
        AVG(total_revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2
    ) AS moving_avg_3m,
    ROUND(
        AVG(total_revenue) OVER (ORDER BY month ROWS BETWEEN 5 PRECEDING AND CURRENT ROW), 2
    ) AS moving_avg_6m
FROM vw_monthly_kpi_summary
ORDER BY month;

-- Q11. Quarterly growth, QoQ and YoY, straight from the view
SELECT
    yr AS year,
    qtr AS quarter,
    quarter_revenue,
    qoq_growth_pct,
    yoy_growth_pct
FROM vw_quarterly_growth
ORDER BY yr, qtr;

-- Q12. Supplier ranking using a weighted composite score
SELECT
    supplier_id,
    supplier_name,
    actual_avg_delay,
    on_time_delivery_pct,
    fill_rate_pct,
    reliability_score,
    -- weights: on-time 30%, fill rate 30%, reliability 40%
    ROUND(
        (on_time_delivery_pct * 0.3) +
        (fill_rate_pct * 0.3) +
        (reliability_score * 0.4), 2
    ) AS composite_score,
    RANK() OVER (ORDER BY
        (on_time_delivery_pct * 0.3) +
        (fill_rate_pct * 0.3) +
        (reliability_score * 0.4) DESC
    ) AS overall_rank
FROM vw_supplier_performance
ORDER BY overall_rank
LIMIT 10;

-- Q13. Product count and revenue per ABC class
SELECT
    abc_class,
    COUNT(*) AS product_count,
    ROUND(SUM(total_revenue), 2) AS class_revenue,
    ROUND(AVG(cumulative_pct), 2) AS avg_cumulative_pct
FROM vw_abc_classification
GROUP BY abc_class
ORDER BY abc_class;

-- Q14. Split products into revenue quartiles with NTILE
SELECT
    product_id,
    product_name,
    category,
    total_revenue,
    NTILE(4) OVER (ORDER BY total_revenue DESC) AS revenue_quartile
FROM (
    SELECT p.product_id, p.product_name, p.category,
           ROUND(SUM(f.revenue), 2) AS total_revenue
    FROM fact_sales_inventory f
    JOIN products p ON f.product_id = p.product_id
    GROUP BY p.product_id, p.product_name, p.category
) t
ORDER BY revenue_quartile, total_revenue DESC;

-- ============================================================
-- STOCKOUT & SUPPLY CHAIN (Q15–Q20)
-- ============================================================

-- Q15. Bucket delivery delays and see how stockout rate changes (root cause check)
SELECT
    CASE
        WHEN delivery_delay_days <= 1 THEN '0-1 days'
        WHEN delivery_delay_days <= 3 THEN '2-3 days'
        WHEN delivery_delay_days <= 5 THEN '4-5 days'
        ELSE '6+ days'
    END AS delay_bucket,
    COUNT(*) AS record_count,
    ROUND(AVG(stockout_flag) * 100, 2) AS stockout_rate_pct,
    ROUND(AVG(units_sold), 2) AS avg_units_sold,
    ROUND(SUM(revenue), 2) AS total_revenue
FROM fact_sales_inventory
GROUP BY
    CASE
        WHEN delivery_delay_days <= 1 THEN '0-1 days'
        WHEN delivery_delay_days <= 3 THEN '2-3 days'
        WHEN delivery_delay_days <= 5 THEN '4-5 days'
        ELSE '6+ days'
    END
ORDER BY delay_bucket;

-- Q16. Dead stock products and how much capital is sitting trapped in them
SELECT
    d.product_id,
    d.product_name,
    d.category,
    d.turnover_ratio,
    d.avg_inventory,
    p.unit_cost,
    ROUND(d.avg_inventory * p.unit_cost, 2) AS trapped_capital
FROM vw_dead_stock d
JOIN products p ON d.product_id = p.product_id
ORDER BY trapped_capital DESC
LIMIT 20;

-- Q17. Stores with the worst stockout rate (need attention)
SELECT
    store_id,
    store_name,
    city,
    total_revenue,
    stockout_rate_pct,
    stockout_rank
FROM vw_store_ranking
ORDER BY stockout_rate_pct DESC
LIMIT 10;

-- Q18. Category-wise stockout + fill rate
SELECT
    category,
    product_count,
    total_revenue,
    revenue_contribution_pct,
    stockout_rate_pct,
    avg_inventory
FROM vw_category_kpi
ORDER BY revenue_contribution_pct DESC;

-- Q19. Warehouse utilization vs stockouts and delays
SELECT
    warehouse_id,
    warehouse_name,
    capacity_units,
    avg_inventory,
    utilization_pct,
    total_stockouts,
    avg_delay,
    total_revenue
FROM vw_warehouse_performance
ORDER BY utilization_pct DESC;

-- Q20. Yearly revenue trend with YoY growth (CTE + LAG)
WITH yearly AS (
    SELECT
        YEAR(date) AS yr,
        ROUND(SUM(revenue), 2) AS yearly_revenue,
        SUM(units_sold) AS yearly_units
    FROM fact_sales_inventory
    GROUP BY YEAR(date)
)
SELECT
    yr AS year,
    yearly_revenue,
    yearly_units,
    LAG(yearly_revenue) OVER (ORDER BY yr) AS prev_year_revenue,
    ROUND(
        (yearly_revenue - LAG(yearly_revenue) OVER (ORDER BY yr))
        / NULLIF(LAG(yearly_revenue) OVER (ORDER BY yr), 0) * 100, 2
    ) AS yoy_growth_pct
FROM yearly
ORDER BY yr;

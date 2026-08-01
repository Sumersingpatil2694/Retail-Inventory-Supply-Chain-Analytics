# 📦 Retail Inventory Optimization & Supply Chain Analytics

### End-to-End Business Data Analytics Project

**Author:** Sumersing Patil  
**Role:** Data Analyst  
**Tech Stack:** Python • Pandas • NumPy • Matplotlib • MySQL • SQL • Excel • Tableau  

---

## 🎯 Business Problem

A multi-store retail chain operating across **25 stores**, **8 warehouses**, and **20 suppliers** is experiencing:
- **Stockouts** leading to lost sales and customer dissatisfaction
- **Excess inventory** tying up working capital and increasing carrying costs
- **Supplier delivery delays** disrupting replenishment cycles
- **Inefficient inventory planning** caused by lack of data-driven reorder signals

Management needs a **data-driven analytics solution** to identify inefficiencies, measure KPIs, and take corrective action.

---

## 🎯 Project Objectives

| # | Objective | Business Value |
|---|-----------|----------------|
| 1 | Assess data quality and clean raw transactional data | Reliable analytics foundation |
| 2 | Calculate core business KPIs (Revenue, Turnover, Fill Rate, Stockout Rate) | Performance measurement |
| 3 | Identify top/bottom performing products, stores, suppliers, and categories | Resource prioritization |
| 4 | Detect dead stock, fast-movers, and slow-movers using ABC/XYZ classification | Inventory optimization |
| 5 | Analyze seasonal trends and promotional impact on revenue | Demand planning |
| 6 | Quantify revenue impact of stockouts | Financial risk assessment |
| 7 | Generate rule-based reorder recommendations | Operational decision support |
| 8 | Prepare dashboard-ready datasets for Tableau and Excel | Executive reporting |

---

## 📊 Dataset Summary

| Dataset Component | Count | Description |
|---|---|---|
| Raw Transaction Records | 50,301 | Daily store-product level sales & inventory data |
| Products | 410 | Across 6 categories (Electronics, Furniture, Clothing, etc.) |
| Retail Stores | 25 | Across major Indian cities |
| Warehouses | 8 | Regional distribution centers |
| Suppliers | 20 | Domestic + international |
| Time Period | 4 Years | Jan 2021 – Dec 2024 |

---

## 🔄 Analytics Workflow

```
Raw Data → Data Quality Assessment → Data Cleaning → Feature Engineering
    → EDA → KPI Analysis → Advanced Analytics (ABC/XYZ, Pareto, Trends)
    → Root Cause Analysis → Business Recommendations → Tableau/Excel Dashboard
```

---

## 📁 Project Structure

```
Retail Inventory & Supply Chain Performance Analytics/
│
├── data/                               # Raw + processed CSV files
│   ├── fact_sales_inventory_RAW.csv         # Raw data (50,301 rows)
│   ├── fact_sales_inventory_CLEANED.csv     # Cleaned data, MySQL-ready
│   ├── fact_sales_inventory_analytics.csv   # Analytics-ready (with dimensions merged)
│   ├── products.csv                         # Product dimension (410 products)
│   ├── stores.csv                           # Store dimension (25 stores)
│   ├── suppliers.csv                        # Supplier dimension (20 suppliers)
│   └── warehouses.csv                       # Warehouse dimension (8 warehouses)
│
├── SQL/                                # SQL scripts
│   ├── schema.sql                           # Database schema (MySQL 8.0+)
│   ├── views.sql                            # Analytical views
│   └── business_queries.sql                 # Ad-hoc business queries
│
├── Mysql_data_loader.py                # CSV → MySQL data loader (root-level script)
├── export_datasets.py                  # MySQL views → CSV exporter (root-level script)
│
├── Retail_Inventory_Analytics.ipynb    # Jupyter notebook (Python-side cleaning + analytics)
│
├── Clean Data/                         # Dashboard-ready CSVs exported BY THE NOTEBOOK
│   ├── monthly_kpi.csv
│   ├── category_performance.csv
│   ├── store_performance.csv
│   ├── supplier_performance.csv
│   ├── abc_classification.csv
│   ├── inventory_turnover.csv
│   ├── reorder_recommendations.csv
│   └── stockout_revenue_impact.csv
│
├── SQL_data/                           # Dashboard-ready CSVs exported BY export_datasets.py (from MySQL views)
│   ├── monthly_kpi_summary.csv
│   ├── category_kpi.csv
│   ├── store_ranking.csv
│   ├── supplier_performance.csv
│   ├── abc_classification.csv
│   ├── inventory_turnover.csv
│   ├── reorder_recommendation.csv
│   ├── stockout_overstock.csv
│   ├── dead_stock.csv
│   ├── quarterly_growth.csv
│   ├── regional_performance.csv
│   └── warehouse_performance.csv
│
├── .env.example                        # Template showing which env vars are used (no real secrets)
├── .gitignore
├── README.md
└── requirements.txt
```

> **Note:** there are two parallel sets of KPI exports — `Clean Data/` (produced by the Python notebook)
> and `SQL_data/` (produced by `export_datasets.py` from the MySQL views). They cover overlapping ground
> from two different engines, so treat `SQL_data/` as the source of truth for anything going into MySQL-driven
> dashboards, and `Clean Data/` as the notebook's own analysis output.

---

## 🚀 How to Run This Project

### Prerequisites
- Python 3.9+
- MySQL 8.0+
- pip package manager

### Step 1: Install Python Dependencies
```bash
pip install -r requirements.txt
```

### Step 2: Create the Database
```sql
-- Open MySQL Workbench or CLI and run:
source SQL/schema.sql;
```

### Step 3: Load Data into MySQL
```bash
# Set your MySQL password — pick ONE of these two options:

# Option A (recommended): local .env file, auto-loaded by the scripts
cp .env.example .env
# then edit .env and set: DB_PASSWORD=your_mysql_password
# .env is gitignored, so this never gets committed.

# Option B: a real shell environment variable instead
# PowerShell:
$env:DB_PASSWORD = "your_mysql_password"
# macOS/Linux:
export DB_PASSWORD="your_mysql_password"

# Run the data loader (root-level script)
python Mysql_data_loader.py
```

### Step 4: Create Analytical Views
```sql
source SQL/views.sql;
```

### Step 5: Run Business Queries
```sql
source SQL/business_queries.sql;
```

### Step 6: Export MySQL Views to CSV (for dashboards)
```bash
# Uses the same DB_PASSWORD environment variable as Step 3
python export_datasets.py
```
Writes dashboard-ready CSVs to `SQL_data/`.

### Step 7: Open the Jupyter Notebook
```bash
jupyter notebook Retail_Inventory_Analytics.ipynb
```
Run all cells from top to bottom. The notebook:
- Loads and cleans the raw data
- Creates the analytics dataset
- Performs EDA and advanced analytics
- Exports dashboard-ready CSV files to `Clean Data/`

---

## 📈 Key Analytical Methods

| Method | Purpose | Tool |
|--------|---------|------|
| Data Quality Assessment | Identify missing, invalid, duplicate, outlier records | Python / Pandas |
| Data Cleaning Pipeline | Standardize dates, text, impute missing values | Python / Pandas |
| KPI Calculation | Revenue, Profit, Turnover, Fill Rate, Stockout Rate | Python + SQL |
| ABC / Pareto Classification | Prioritize products by revenue contribution (80/20) | Python + SQL |
| XYZ Demand Variability | Classify products by demand stability (CV) | Python |
| Inventory Turnover Analysis | Identify fast/slow movers and dead stock | Python + SQL |
| Trend Analysis | Monthly, YoY, MoM, quarterly growth | Python + SQL |
| Correlation Analysis | Delivery delay ↔ stockout relationship | Python |
| Statistical Significance Testing | t-test for promotional revenue lift | Python / SciPy |
| Root Cause Analysis | Delay → stockout → revenue loss chain | Python + SQL |
| Rule-Based Recommendation Engine | Reorder urgency classification | Python |
| Stockout Revenue Impact | Estimate financial loss from stockouts | Python |

---

## 💡 Key Business Insights

1. **Electronics** is the top revenue category — priority for inventory investment.
2. Supplier delivery delay ranges from **0.48 to 4.06 days** — clear renegotiation candidates.
3. Stockout rate jumps from **0.02%** (0–1 day delay) to **4.55–6.51%** (2+ day delay) — delay is a real stockout driver.
4. **ABC analysis** confirms ~20% of products drive 80% of revenue — focus control on Class A.
5. Dead stock products (turnover < 0.5) trap working capital — liquidation recommended.
6. Promotional/holiday revenue lift is **not statistically significant** at aggregate level — evaluate at category level.

---

## 📊 SQL Views Created (12 total)

| View | Description |
|------|-------------|
| `vw_inventory_turnover` | Product-level turnover ratio |
| `vw_dead_stock` | Products with turnover < 0.5 |
| `vw_stockout_overstock` | Per product-store stockout/overstock rates |
| `vw_supplier_performance` | Supplier scorecard with delay, fill rate, ranking |
| `vw_regional_performance` | City-level revenue ranking |
| `vw_warehouse_performance` | Warehouse utilization and stockouts |
| `vw_reorder_recommendation` | Products needing reorder (latest inventory vs reorder point) |
| `vw_monthly_kpi_summary` | Monthly revenue, units, stockout, fill rate |
| `vw_abc_classification` | Pareto-based ABC product classification |
| `vw_store_ranking` | Store ranking by revenue and stockout |
| `vw_category_kpi` | Category-level KPI summary |
| `vw_quarterly_growth` | QoQ + YoY growth using LAG window function |

---

## 🛠️ Business Queries Included (20 total)

- **Basic Analytics (Q1–Q6):** Slow movers, worst supplier, top products, reorder alerts, promo impact, weather impact
- **Advanced Window Functions (Q7–Q14):** ROW_NUMBER top-N per category, DENSE_RANK store ranking, running totals, moving averages, quarterly growth, composite supplier scoring, ABC summary, NTILE quartiles
- **Stockout & Supply Chain (Q15–Q20):** Delay buckets vs stockout, dead stock capital, store stockout ranking, category KPI, warehouse utilization, yearly YoY growth

---

## 📋 Tableau Dashboard Preparation

The following pre-aggregated CSV files are exported for Tableau:

| Export File | Granularity | Key Measures |
|-------------|-------------|--------------|
| `monthly_kpi.csv` | Month | Revenue, Units, Stockout%, Fill Rate% |
| `category_performance.csv` | Category | Revenue, Profit, Units, Stockout% |
| `store_performance.csv` | Store | Revenue, Units, Stockout%, Rank |
| `supplier_performance.csv` | Supplier | Delay, On-time%, Fill Rate, Rank |
| `abc_classification.csv` | Product | Revenue, Cumulative%, ABC Class |
| `inventory_turnover.csv` | Product | Turnover Ratio, Units Sold, Avg Inventory |
| `reorder_recommendations.csv` | Store-Product | Inventory, Reorder Point, Gap, Urgency |
| `stockout_revenue_impact.csv` | Product | Estimated Revenue Lost, Stockout Days |

### Suggested Tableau Calculated Fields
- `Profit Margin % = SUM([Profit]) / SUM([Revenue]) * 100`
- `Stockout Rate % = SUM([Stockout Flag]) / COUNT([Records]) * 100`
- `Fill Rate % = SUM([Units Received]) / SUM([Units Ordered]) * 100`
- `Inventory Turnover = SUM([Units Sold]) / AVG([Inventory Level])`
- `YoY Growth % = (SUM([Revenue]) - LOOKUP(SUM([Revenue]), -12)) / LOOKUP(SUM([Revenue]), -12) * 100`

---

## 📊 Excel Dashboard Preparation

### Recommended Pivot Tables
1. **Revenue by Category × Year** — pivot table with conditional formatting (data bars)
2. **Store Performance Dashboard** — pivot table with rank + stockout rate
3. **Supplier Scorecard** — pivot table with delay, fill rate, composite score
4. **Monthly KPI Trend** — pivot chart (line chart for revenue trend)
5. **ABC Classification Summary** — pivot table with product count per class

### Recommended Excel Features
- **Slicers:** Category, Store, Supplier, Year, Season
- **Conditional Formatting:** Data bars on revenue, color scales on stockout rate
- **KPI Cards:** Total Revenue, Stockout Rate, Avg Fill Rate, Total Profit
- **Pivot Charts:** Bar chart (category revenue), Line chart (monthly trend)

---

## 💼 Business Impact

- ✅ Reduce stockouts by identifying high-risk products and stores
- ✅ Reduce excess inventory costs through ABC/XYZ classification
- ✅ Improve supplier performance monitoring with delivery scorecards
- ✅ Increase inventory turnover with data-driven reorder recommendations
- ✅ Enable executive decision-making via KPI dashboards

---

## 📝 Assumptions & Limitations

### Assumptions
- Estimated profit uses unit_cost from product dimension; actual costs may vary.
- Estimated stockout revenue loss is a business approximation based on historical averages.
- Reorder recommendations use predefined business rules, not predictive forecasting.
- ABC uses 80/15/5 split; XYZ uses CV thresholds of 0.5 and 1.0 (industry standard).

### Limitations
- Dataset is historical — no future demand data.
- No customer-level purchasing behavior available.
- Transportation, supplier pricing changes, and warehouse operating costs excluded.
- Recommendation engine is rule-based (no ML forecasting).
- Weather/season data is observational — causal claims are limited.

---

## 📦 Requirements

```
pandas>=2.0.0
numpy>=1.24.0
matplotlib>=3.7.0
scipy>=1.10.0
sqlalchemy>=2.0.0
pymysql>=1.1.0
jupyter>=1.0.0
```

---

## 📄 License

This project is created for educational and portfolio purposes.

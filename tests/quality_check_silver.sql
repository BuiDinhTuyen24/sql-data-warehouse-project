/*
===================================================================================
Quality checks
===================================================================================
Scripts purpose:
  This scripts perform a plenty of checks for accuracy, standard and consistency
  across the silver schema, including:
    - Nulls or invalid primary keys
    - Unwanted space in string field
    - Out of range date
    - Data standardization and consistency
    - Data uniform between related fields
Usage notes:
    - Run this scripts after loading the silver layer
    - Investigate and fix any problems found after running the scripts
===================================================================================
*/
-- crm_cust_info
-- Check for Nulls or Duplicates in primary keys
-- Expectation: No results
SELECT 
	cst_id,
	COUNT(*)
FROM silver.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1 OR cst_id IS NULL;

-- Remove Nulls or Duplicates in primary keys
SELECT *
FROM (SELECT 
	*,
	ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
FROM silver.crm_cust_info)t
WHERE flag_last = 1;

-- Check for unwanted space
-- Expectation: No results
SELECT 
	cst_firstname
FROM silver.crm_cust_info
WHERE cst_firstname != TRIM(cst_firstname);

-- INSERT THE CLEANED DATA
INSERT INTO silver.crm_cust_info (
	cst_id,
	cst_key,
	cst_firstname,
	cst_lastname,
	cst_marital_status,
	cst_gndr,
	cst_create_date
)
SELECT 
	cst_id,
	cst_key,
	TRIM(cst_firstname) AS cst_firstname,
	TRIM(cst_lastname) AS cst_lastname,
	CASE WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
		 WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
		 ELSE 'n/a'
		 END AS cst_marital_status,
	CASE WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
		 WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
		 ELSE 'n/a'
		 END AS cst_gndr,
	cst_create_date
FROM (SELECT 
	*,
	ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
FROM silver.crm_cust_info
WHERE cst_id IS NOT NULL)t
WHERE flag_last = 1;


-- crm_prd_info
-- Check for Nulls or Duplicates in Primary key
-- Expectation: No results
SELECT 
	prd_id,
	COUNT(*)
FROM silver.crm_prd_info
GROUP BY prd_id
HAVING COUNT(*) > 1 OR prd_id IS NULL;

-- Check for unwanted space
-- Expectation: No results
SELECT 
	prd_nm
FROM silver.crm_prd_info
WHERE prd_nm != TRIM(prd_nm);

-- Check for NULLS or Negative numbers
-- Expectation: No results
SELECT
	prd_cost
FROM silver.crm_prd_info
WHERE prd_cost < 0 OR prd_cost IS NULL;

-- Data standardization and consistency
-- Expectation: No results
SELECT DISTINCT
	prd_line
FROM silver.crm_prd_info;

-- Check for Invalid Date Orders
-- Expectation: No results
SELECT *
FROM silver.crm_prd_info
WHERE prd_end_dt < prd_start_dt;

-- INSERT THE CLEANED DATA
INSERT INTO silver.crm_prd_info(
	prd_id,
	cat_id,
	prd_key,
	prd_nm,
	prd_cost,
	prd_line,
	prd_start_dt,
	prd_end_dt
)
SELECT
	prd_id,
	REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,
	SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,
	prd_nm,
	ISNULL(prd_cost, 0) AS prd_cost,
	CASE WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
		 WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
		 WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
		 WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
		 ELSE 'n/a' 
	END AS prd_line,
	CAST(prd_start_dt AS DATE) AS prd_start_dt,
	CAST(LEAD(prd_start_dt) OVER(PARTITION BY prd_key ORDER BY prd_start_dt)-1 AS DATE) AS prd_end_dt
FROM silver.crm_prd_info;


-- Sales Details information
-- Checking for invalid dates
SELECT
	NULLIF(sls_order_dt, 0)
FROM silver.crm_sales_details
WHERE sls_order_dt <= 0 
OR LEN(sls_order_dt) != 8
OR sls_order_dt > 20500101
OR sls_order_dt < 19000101;

SELECT
	NULLIF(sls_ship_dt, 0)
FROM silver.crm_sales_details
WHERE sls_ship_dt <= 0 
OR LEN(sls_ship_dt) != 8
OR sls_ship_dt > 20500101
OR sls_ship_dt < 19000101;

SELECT
	NULLIF(sls_due_dt, 0)
FROM silver.crm_sales_details
WHERE sls_due_dt <= 0 
OR LEN(sls_due_dt) != 8
OR sls_due_dt > 20500101
OR sls_due_dt < 19000101;

-- Check data consistency: Sales, Quantity and price
SELECT DISTINCT
    sls_quantity,
	CASE WHEN sls_price IS NULL OR sls_price <= 0 THEN sls_sales/NULLIF(sls_quantity, 0) ELSE sls_price
	END AS sls_price,
	CASE WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity*ABS(sls_price) THEN sls_quantity*ABS(sls_price) 
		 ELSE sls_sales
	END AS sls_sales
FROM silver.crm_sales_details
WHERE sls_sales != sls_quantity * sls_price
OR sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL
OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
ORDER BY sls_sales, sls_quantity, sls_price;

-- Insert the cleaned data
INSERT INTO silver.crm_sales_details (
	sls_ord_num,
	sls_prd_key,
	sls_cust_id,
	sls_order_dt,
	sls_ship_dt,
	sls_due_dt,
	sls_sales,
	sls_quantity,
	sls_price
)
SELECT
    sls_ord_num,
    sls_prd_key,
    sls_cust_id,
    CASE WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL
         ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
    END sls_order_dt,
    CASE WHEN sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL
         ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
    END sls_ship_dt,
    CASE WHEN sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL
         ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
    END sls_due_dt,
    sls_quantity,
	CASE WHEN sls_price IS NULL OR sls_price <= 0 THEN sls_sales/NULLIF(sls_quantity, 0) ELSE sls_price
	END AS sls_price,
	CASE WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity*ABS(sls_price) THEN sls_quantity*ABS(sls_price) 
		 ELSE sls_sales
	END AS sls_sales
FROM silver.crm_sales_details;


-- erp_cust_az12
-- Trimming the cid to match the customer infomation
SELECT 	
	CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
		 ELSE cid
	END AS cid,
	bdate,
	gen
FROM silver.erp_cust_az12;

-- Identify out of range date
SELECT DISTINCT
	bdate
FROM silver.erp_cust_az12
WHERE bdate < '1924-01-01' OR bdate > GETDATE();

-- Data standardization & consistency
SELECT DISTINCT gen
FROM silver.erp_cust_az12;

-- Insert the data
INSERT INTO silver.erp_cust_az12(
	cid,
	bdate,
	gen
)
SELECT 	
	CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
		 ELSE cid
	END AS cid,
	CASE WHEN bdate > GETDATE() THEN NULL
		 ELSE bdate
	END AS bdate,
	CASE WHEN UPPER(TRIM(gen)) IN ('F','FEMALE') THEN 'Female'
		 WHEN UPPER(TRIM(gen)) IN ('M','MALE') THEN 'Male'
		 ELSE 'n/a'
	END AS gen
FROM silver.erp_cust_az12;


-- erp_loc_a101
-- Replace the '-' 
SELECT
	REPLACE(cid, '-', '') AS cid,
	cntry
FROM silver.erp_loc_a101;

-- Data standardization & consistency
SELECT DISTINCT cntry
FROM silver.erp_loc_a101
ORDER BY cntry;

SELECT
	REPLACE(cid, '-', '') AS cid,
	CASE WHEN TRIM(cntry) = 'DE' THEN 'Germany'
		 WHEN TRIM(cntry) IN ('United States','US', 'USA') THEN 'United States'
		 WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
		 ELSE TRIM(cntry)
	END AS cntry
FROM silver.erp_loc_a101;

-- Insert the date
INSERT INTO silver.erp_loc_a101 (
	cid,
	cntry
)
SELECT
	REPLACE(cid, '-', '') AS cid,
	CASE WHEN TRIM(cntry) = 'DE' THEN 'Germany'
		 WHEN TRIM(cntry) IN ('United States','US', 'USA') THEN 'United States'
		 WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
		 ELSE TRIM(cntry)
	END AS cntry
FROM silver.erp_loc_a101;


-- erp.px_cat_g1v2
-- Check for unwanted space
SELECT 
	id,
	cat,
	subcat,
	maintenance
FROM silver.erp_px_cat_g1v2
WHERE cat != TRIM(cat) OR subcat != TRIM(subcat) OR maintenance != TRIM(maintenance);

-- Standardization & Consistency
SELECT DISTINCT
	subcat
FROM silver.erp_px_cat_g1v2;

-- Insert the date
INSERT INTO silver.erp_px_cat_g1v2(
	id,
	cat,
	subcat,
	maintenance
)
SELECT 
	id,
	cat,
	subcat,
	maintenance
FROM silver.erp_px_cat_g1v2;

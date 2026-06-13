{{ config(materialized='view') }}

-- Staging layer: clean + enrich source data
-- Source: nessie.demo.products (Iceberg table, tạo bởi iceberg-test Spark job)
-- Output: view trong nessie.<schema>.stg_products

SELECT
    id,
    TRIM(name)                AS name,
    TRIM(LOWER(category))     AS category,
    CAST(price AS DECIMAL(10,2)) AS price,

    -- Phân loại price tier cho downstream analysis
    CASE
        WHEN price < 50    THEN 'budget'
        WHEN price < 500   THEN 'mid-range'
        ELSE                    'premium'
    END AS price_tier

FROM {{ source('demo', 'products') }}

{{ config(
    materialized='table',
    file_format='iceberg',
    location_root='s3a://warehouse/dbt'
) }}

-- Mart layer: business aggregation
-- Output: Iceberg table lakehouse.<schema>.products_by_category
-- Lưu trong MinIO: s3a://warehouse/dbt/<schema>/products_by_category/

SELECT
    category,
    price_tier,
    COUNT(*)                          AS product_count,
    MIN(price)                        AS min_price,
    MAX(price)                        AS max_price,
    ROUND(AVG(price), 2)              AS avg_price,
    ROUND(SUM(price), 2)              AS total_value

FROM {{ ref('stg_products') }}
GROUP BY category, price_tier
ORDER BY category, price_tier

# data-platform-processing

**Source code xử lý dữ liệu** cho Data Lakehouse Platform — tổ chức theo kiến trúc medallion:
- **Spark** (processing): biến đổi dữ liệu bronze → silver → gold.
- **dbt** (modeling): mô hình hóa/aggregation trên lakehouse (Iceberg qua Spark Thrift).

Repo này **chỉ chứa code + Dockerfile đóng gói code**. Việc *chạy* (submit/orchestrate) do
**data-platform-airflow** đảm nhiệm — Airflow là luồng điều phối DUY NHẤT. Config theo env
(schema, threads, spark profiles…) do **data-platform-infra** inject vào Airflow qua
`AIRFLOW_VAR_*`. Repo này **không** phụ thuộc infra (đã bỏ git submodule) và **không** tự submit job.

## Structure

```
dbt/                 # MODELING code (dbt)
  models/
    staging/         # Raw → typed, renamed (silver-ish)
    marts/           # Business-level aggregations (gold)
  sources.yml
  dbt_project.yml
  profiles.yml       # Trỏ Spark Thrift; giá trị env qua env_var(...)
docker/
  dbt/Dockerfile     # Đóng gói dbt project → image cho K8s Job
scripts/
  run-dbt.sh         # Chạy dbt như K8s Job (tạm thời — sau này dbt lên Airflow)
```

> **Sắp có:** thư mục spark application code (`.py`) + `docker/spark/Dockerfile` khi thêm
> Spark job thật. Airflow spec sẽ trỏ tới image build từ đây.

## Kiến trúc — ai làm gì

| Repo | Vai trò |
|---|---|
| **processing** (repo này) | Chỉ chứa **code**: spark (`.py`) + dbt (`.sql`) + Dockerfile đóng gói |
| **airflow** | Điều phối **DUY NHẤT**: DAG + spec submit Spark job; sau này chạy cả dbt |
| **infra** | Platform (helmfile) + inject config vào Airflow qua `AIRFLOW_VAR_*` |

Spark profiles (small/medium/large/xlarge) do infra inject vào Airflow (`AIRFLOW_VAR_SPARK_PROFILES`);
DAG chọn profile lúc trigger — processing **không** giữ profiles.

## Usage — dbt (tạm thời)

```bash
# Chạy dbt như một K8s Job (image dbt build từ docker/dbt/Dockerfile)
./scripts/run-dbt.sh stg run
./scripts/run-dbt.sh stg run --select staging
./scripts/run-dbt.sh stg test
./scripts/run-dbt.sh stg debug        # test kết nối Spark Thrift
```

`run-dbt.sh` là bước quá độ; khi dbt chuyển vào Airflow, script này sẽ được thay bằng một dbt DAG.

## Environments

Branch = env: `stg` / `uat` / `prd`. Code **giống hệt nhau trên mọi env** — chạy ở env nào thì
đọc config env đó (do Airflow/infra cấp lúc runtime). Promote stg → uat → prd chỉ bằng merge PR.

Catalog: `lakehouse` (Iceberg HiveCatalog → HMS thrift:9083).
Ví dụ: `spark.sql("SELECT * FROM lakehouse.demo.products")`.

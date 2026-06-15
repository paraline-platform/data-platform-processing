# data-platform-processing

dbt models + Spark jobs for the Data Lakehouse Platform. Depends on `data-platform-infra` (mounted as git submodule at `./platform`) for environment config and spark profiles.

## Structure

```
dbt/
  models/
    staging/       # Raw → typed, renamed
    marts/         # Business-level aggregations
  macros/
  sources.yml
  dbt_project.yml
spark-jobs/        # SparkApplication YAMLs (submitted via Spark Operator)
docker/
  dbt/Dockerfile   # dbt image for CI/K8s Job
scripts/
  run-dbt.sh       # Run dbt as K8s Job (reads platform/environments/<env>.yaml)
  run-spark-job.sh # Submit SparkApplication via Helm chart
  sync-platform.sh # Đồng bộ submodule platform với infra branch tương ứng
platform/          # git submodule → data-platform-infra (tự động bump bởi CI)
```

## Setup

```bash
# Clone with submodule (required — scripts read platform/environments/)
git clone --recurse-submodules https://github.com/tungnt763/data-platform-processing.git

# If already cloned without --recurse-submodules:
git submodule update --init
```

## Submodule Strategy

`platform/` là git submodule trỏ vào `data-platform-infra`. Mỗi branch của repo này tương ứng với 1 branch của infra:

| Branch (processing) | Branch (infra) | Helmfile env |
|---|---|---|
| `stg` | `stg` | dev |
| `uat` | `uat` | uat |
| `prd` | `prd` | prod |

**Tự động (CI):** Khi infra có push mới lên `stg/uat/prd`, workflow `bump-processing-submodule.yml` (trong infra repo) tự động commit submodule bump vào branch tương ứng của processing. Không cần làm thủ công.

**Thủ công (local dev):**

```bash
# Đồng bộ với infra branch tương ứng (auto-detect từ current branch)
./scripts/sync-platform.sh

# Hoặc chỉ định branch cụ thể:
./scripts/sync-platform.sh stg
```

**Không conflict khi promote:** `.gitmodules` giống nhau trên mọi branch (không có `branch =`) → merge stg→uat→prd không bao giờ conflict ở file này.

## Usage

```bash
# Run dbt (spins up K8s Job)
./scripts/run-dbt.sh dev run
./scripts/run-dbt.sh dev run --select staging
./scripts/run-dbt.sh dev test
./scripts/run-dbt.sh dev debug        # test Thrift connection

# Submit Spark job
./scripts/run-spark-job.sh dev small lakehouse-namespace-setup
./scripts/run-spark-job.sh dev small iceberg-test

# Catalog: lakehouse (Iceberg HiveCatalog → HMS thrift:9083)
# Dùng: spark.sql("SELECT * FROM lakehouse.demo.products")
```

## Environments

Config lives in `platform/environments/<env>.yaml` (from submodule). Spark profiles live in `platform/spark-profiles/<env>.yaml`.

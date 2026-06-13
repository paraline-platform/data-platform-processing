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
platform/          # git submodule → data-platform-infra
```

## Setup

```bash
# Clone with submodule (required — scripts read platform/environments/)
git clone --recurse-submodules https://github.com/tungnt763/data-platform-processing.git

# If already cloned without --recurse-submodules:
git submodule update --init --recursive
```

## Usage

```bash
# Run dbt (spins up K8s Job)
./scripts/run-dbt.sh dev run
./scripts/run-dbt.sh dev run --select staging
./scripts/run-dbt.sh dev test
./scripts/run-dbt.sh dev debug        # test Thrift connection

# Submit Spark job
./scripts/run-spark-job.sh dev dev spark-pi
./scripts/run-spark-job.sh dev dev iceberg-test

# Update infra submodule to latest
git submodule update --remote platform
git add platform && git commit -m "chore: bump infra submodule"
```

## Environments

Config lives in `platform/environments/<env>.yaml` (from submodule). Spark profiles live in `platform/spark-profiles/<env>.yaml`.

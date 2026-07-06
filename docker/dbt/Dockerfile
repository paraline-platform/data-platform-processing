# dbt image chạy như K8s Job trong cluster (P2.1)
# Project + profiles bake sẵn — Job chỉ cần image + env vars, không ConfigMap,
# không pip install lúc runtime (startup ~10s thay vì ~3 phút).
FROM python:3.11-slim

WORKDIR /dbt

# Cài dbt (explicit <2.0.0 vì dbt-core 2.0 bỏ Spark adapter)
RUN pip install --no-cache-dir \
    "dbt-core>=1.8.0,<2.0.0" \
    "dbt-spark[PyHive]>=1.8.0,<2.0.0"

# COPY dbt project (kèm profiles.yml — không chứa secret, config qua env vars)
COPY dbt/ .

ENV DBT_PROFILES_DIR=/dbt

ENTRYPOINT ["dbt"]
CMD ["--help"]

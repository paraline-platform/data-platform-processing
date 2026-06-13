# dbt image chạy như K8s Job trong cluster
# Cài dbt + COPY project files → không cần ConfigMap thủ công
FROM python:3.11-slim

WORKDIR /dbt

# Cài dbt (explicit <2.0.0 vì dbt-core 2.0 bỏ Spark adapter)
RUN pip install --no-cache-dir \
    "dbt-core>=1.8.0,<2.0.0" \
    "dbt-spark[PyHive]>=1.8.0,<2.0.0"

# COPY dbt project vào image
COPY dbt/ .

# profiles.yml được inject lúc chạy qua env var hoặc K8s Secret mount
# Không hardcode credentials vào image
ENTRYPOINT ["dbt"]
CMD ["--help"]

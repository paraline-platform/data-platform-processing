#!/usr/bin/env bash
# ============================================================
# RUN-DBT.SH — Chạy dbt models như K8s Job
# ============================================================
# Usage:
#   ./scripts/run-dbt.sh <env> <command> [dbt-options...]
#
# Arguments:
#   env     : dev | uat | prod
#   command : run | test | debug | compile | docs generate (default: run)
#   options : bất kỳ flags nào của dbt (--select, --full-refresh, --target, ...)
#
# Examples:
#   ./scripts/run-dbt.sh dev run
#   ./scripts/run-dbt.sh dev run --select staging
#   ./scripts/run-dbt.sh dev run --select marts --full-refresh
#   ./scripts/run-dbt.sh dev test
#   ./scripts/run-dbt.sh dev debug                       # test connection
#   ./scripts/run-dbt.sh uat run --select marts
#   ./scripts/run-dbt.sh prod run --full-refresh
#
# Cách hoạt động:
#   1. Đọc config (thrift host, schema, threads) từ environments/<env>.yaml
#   2. Tạo ConfigMap với dbt project files + profiles.yml cho env
#   3. Tạo K8s Job: busybox setup dirs + python:3.11-slim runs dbt
#   4. Stream logs → xem kết quả trực tiếp
# ============================================================

set -euo pipefail

# --- Args ---
ENV=${1:?$'Usage: ./scripts/run-dbt.sh <env> [command] [options]\nExample: ./scripts/run-dbt.sh dev run'}
COMMAND=${2:-run}
shift 2 || true          # Bỏ 2 args đầu, còn lại là dbt options
DBT_OPTS="${*:-}"        # Ví dụ: "--select staging --full-refresh"

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DBT_DIR="$ROOT_DIR/dbt"
# INFRA_DIR: platform/ = submodule root (data-platform-infra), platform config lives inside platform/
INFRA_DIR="$ROOT_DIR/platform/platform"
ENV_FILE="$INFRA_DIR/environments/${ENV}.yaml"

# --- Validate ---
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Environment file not found: $ENV_FILE"
  echo "       Available envs: $(ls "$INFRA_DIR/environments/" | sed 's/.yaml//' | tr '\n' ', ')"
  exit 1
fi
if [[ ! -f "$DBT_DIR/dbt_project.yml" ]]; then
  echo "ERROR: dbt project not found at $DBT_DIR/dbt_project.yml"
  exit 1
fi

# --- Read config từ env file (dùng grep/awk thay vì yq để không cần cài thêm) ---
DBT_THREADS=$(grep -A3 "^dbt:" "$ENV_FILE" | grep "threads:" | awk '{print $2}' | tr -d '"' || echo "1")
DBT_SCHEMA=$(grep -A3 "^dbt:" "$ENV_FILE" | grep "schema:" | awk '{print $2}' | tr -d '"' || echo "dbt_${ENV}")

THRIFT_HOST="spark-thrift-server.data-modeling.svc.cluster.local"
NAMESPACE="data-modeling"

# --- Job name (unique per run) ---
JOB_NAME="dbt-${COMMAND}-$(date +%s)"

# --- Print info ---
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Running dbt Job                                         ║"
echo "╠══════════════════════════════════════════════════════════╣"
printf "║  Env       : %-44s║\n" "$ENV"
printf "║  Command   : %-44s║\n" "dbt $COMMAND $DBT_OPTS"
printf "║  Schema    : %-44s║\n" "$DBT_SCHEMA"
printf "║  Threads   : %-44s║\n" "$DBT_THREADS"
printf "║  Thrift    : %-44s║\n" "$THRIFT_HOST:10000"
printf "║  Job name  : %-44s║\n" "$JOB_NAME"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# --- Step 1: Create ConfigMap từ dbt/ files (idempotent) ---
echo "==> [1/3] Creating ConfigMap 'dbt-project' từ dbt/ directory..."

# Profiles.yml được generate động với host/schema/threads cho env
PROFILES_CONTENT="data_platform:
  target: ${ENV}
  outputs:
    ${ENV}:
      type: spark
      method: thrift
      host: ${THRIFT_HOST}
      port: 10000
      schema: ${DBT_SCHEMA}
      threads: ${DBT_THREADS}
      connect_retries: 5
      connect_timeout: 60
      retry_all: true"

# Tạo tmpfile cho profiles.yml (không lưu vào repo vì chứa thông tin kết nối)
TMPDIR_RUN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_RUN"' EXIT
echo "$PROFILES_CONTENT" > "$TMPDIR_RUN/profiles.yml"

# Build ConfigMap từ tất cả dbt files + profiles.yml
kubectl create configmap dbt-project \
  -n "$NAMESPACE" \
  --from-file=dbt_project.yml="$DBT_DIR/dbt_project.yml" \
  --from-file=sources.yml="$DBT_DIR/models/sources.yml" \
  --from-file=stg_products.sql="$DBT_DIR/models/staging/stg_products.sql" \
  --from-file=stg_products_schema.yml="$DBT_DIR/models/staging/schema.yml" \
  --from-file=products_by_category.sql="$DBT_DIR/models/marts/products_by_category.sql" \
  --from-file=marts_schema.yml="$DBT_DIR/models/marts/schema.yml" \
  --from-file=profiles.yml="$TMPDIR_RUN/profiles.yml" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> ConfigMap created/updated."

# --- Step 2: Create K8s Job ---
echo ""
echo "==> [2/3] Creating K8s Job '$JOB_NAME'..."

kubectl apply -f - << MANIFEST
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: dbt
    env: ${ENV}
    dbt-command: ${COMMAND}
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: dbt
        job-name: ${JOB_NAME}
    spec:
      restartPolicy: Never
      initContainers:
        - name: setup
          image: busybox
          command: [sh, -c]
          args:
            - |
              set -e
              mkdir -p /dbt/models/staging /dbt/models/marts /profiles
              cp /cm/dbt_project.yml         /dbt/dbt_project.yml
              cp /cm/sources.yml             /dbt/models/sources.yml
              cp /cm/stg_products.sql        /dbt/models/staging/stg_products.sql
              cp /cm/stg_products_schema.yml /dbt/models/staging/schema.yml
              cp /cm/products_by_category.sql /dbt/models/marts/products_by_category.sql
              cp /cm/marts_schema.yml        /dbt/models/marts/schema.yml
              cp /cm/profiles.yml            /profiles/profiles.yml
              echo "Setup complete. Files:"
              find /dbt -type f | sort
          volumeMounts:
            - name: cm
              mountPath: /cm
            - name: project
              mountPath: /dbt
            - name: profiles
              mountPath: /profiles
      containers:
        - name: dbt
          image: python:3.11-slim
          command: [bash, -c]
          args:
            - |
              set -e
              echo "==> Installing dependencies..."
              apt-get install -qq -y git 2>/dev/null | tail -1
              # dbt 2.0 (Fusion engine) không support spark adapter
              # Explicit <2.0.0 để pip không resolve dbt-core 2.0.0-alpha
              pip install -q \
                "dbt-core>=1.8.0,<2.0.0" \
                "dbt-spark[PyHive]>=1.8.0,<2.0.0" 2>&1 | tail -3
              echo "==> dbt version: \$(dbt --version 2>&1 | head -1)"
              echo ""
              echo "==> Running: dbt ${COMMAND} ${DBT_OPTS}"
              echo "    Target : ${ENV}"
              echo "    Schema : ${DBT_SCHEMA}"
              echo ""
              dbt ${COMMAND} \
                --profiles-dir /profiles \
                --project-dir /dbt \
                --target ${ENV} \
                ${DBT_OPTS}
          resources:
            requests:
              cpu: "200m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "1Gi"
          volumeMounts:
            - name: project
              mountPath: /dbt
            - name: profiles
              mountPath: /profiles
      volumes:
        - name: cm
          configMap:
            name: dbt-project
        - name: project
          emptyDir: {}
        - name: profiles
          emptyDir: {}
MANIFEST

echo "==> Job created."

# --- Step 3: Stream logs ---
echo ""
echo "==> [3/3] Waiting for dbt pod to start..."

# Đợi pod được tạo
for i in $(seq 1 30); do
  POD=$(kubectl get pods -n "$NAMESPACE" -l "job-name=${JOB_NAME}" --no-headers 2>/dev/null | awk '{print $1}' | head -1)
  if [[ -n "$POD" ]]; then
    STATUS=$(kubectl get pod "$POD" -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $3}')
    echo "    Pod: $POD  Status: $STATUS"
    if [[ "$STATUS" != "Pending" ]]; then
      break
    fi
  fi
  sleep 3
done

# Đợi init container xong
echo "==> Waiting for init container to complete..."
kubectl wait --for=condition=initialized "pod/$POD" -n "$NAMESPACE" --timeout=120s 2>/dev/null || true

# Stream logs
echo ""
echo "==> Streaming dbt logs:"
echo "──────────────────────────────────────────────────────────"
kubectl logs -n "$NAMESPACE" "$POD" -c dbt -f 2>/dev/null || \
  kubectl logs -n "$NAMESPACE" "$POD" -f 2>/dev/null || true
echo "──────────────────────────────────────────────────────────"

# Final status — đợi pod hoàn thành trước khi check (tránh race condition)
echo ""
for i in $(seq 1 15); do
  FINAL_STATUS=$(kubectl get pod "$POD" -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $3}')
  if [[ "$FINAL_STATUS" != "Running" ]] && [[ -n "$FINAL_STATUS" ]]; then
    break
  fi
  sleep 2
done

EXIT_CODE=$(kubectl get pod "$POD" -n "$NAMESPACE" \
  -o jsonpath='{.status.containerStatuses[?(@.name=="dbt")].state.terminated.exitCode}' 2>/dev/null || echo "1")

if [[ "${FINAL_STATUS}" == "Completed" ]] && [[ "${EXIT_CODE}" == "0" ]]; then
  echo "==> ✓ dbt $COMMAND SUCCEEDED"
else
  echo "==> ✗ dbt $COMMAND FAILED (pod status: $FINAL_STATUS, exit: $EXIT_CODE)"
  echo "    Xem logs: kubectl logs $POD -n $NAMESPACE -c dbt"
  exit 1
fi

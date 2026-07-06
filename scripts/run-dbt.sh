#!/usr/bin/env bash
# ============================================================
# RUN-DBT.SH — Chạy dbt như K8s Job từ image GHCR (P2.1)
# ============================================================
# Usage:
#   ./scripts/run-dbt.sh <env> [command] [dbt-options...]
#
# Examples:
#   ./scripts/run-dbt.sh dev run
#   ./scripts/run-dbt.sh dev run --select staging
#   ./scripts/run-dbt.sh dev test
#   ./scripts/run-dbt.sh dev debug                 # test Thrift connection
#   DBT_IMAGE=ghcr.io/paraline-platform/dbt:stg-abc1234 ./scripts/run-dbt.sh dev run
#
# So với bản cũ (P2.1 — xem docs/optimization/03 trong infra repo):
#   - KHÔNG pip install lúc runtime (image build sẵn bởi CI) → start ~10s
#   - KHÔNG ConfigMap liệt kê từng file model → thêm model mới zero-touch
#   - KHÔNG grep YAML env file → env config qua env vars (profiles.yml đọc env_var)
#
# Yêu cầu: namespace có quyền pull image GHCR (package public, hoặc
#   kubectl create secret docker-registry ghcr-pull ... -n data-modeling
#   rồi set IMAGE_PULL_SECRET=ghcr-pull)
# ============================================================
set -euo pipefail

ENV=${1:?$'Usage: ./scripts/run-dbt.sh <env> [command] [options]\nExample: ./scripts/run-dbt.sh dev run'}
COMMAND=${2:-run}
shift 2 || true

IMAGE="${DBT_IMAGE:-ghcr.io/paraline-platform/dbt:latest-stg}"   # TODO(P3.7): bắt buộc sha tag
NAMESPACE="data-modeling"
JOB_NAME="dbt-${COMMAND}-$(date +%s)"

# env → schema/threads (khớp environments/<env>.yaml bên infra; đổi ở đây khi đổi bên đó)
case "$ENV" in
  dev)  SCHEMA=dbt_dev;  THREADS=1 ;;
  uat)  SCHEMA=dbt_uat;  THREADS=2 ;;
  prod) SCHEMA=dbt_prod; THREADS=4 ;;
  *) echo "ERROR: env không hợp lệ: $ENV (dev|uat|prod)"; exit 1 ;;
esac

# dbt args → JSON array cho container args
ARGS_JSON="[\"${COMMAND}\", \"--target\", \"${ENV}\""
for a in "$@"; do ARGS_JSON+=", \"${a}\""; done
ARGS_JSON+="]"

PULL_SECRET_BLOCK=""
if [[ -n "${IMAGE_PULL_SECRET:-}" ]]; then
  PULL_SECRET_BLOCK="
      imagePullSecrets:
        - name: ${IMAGE_PULL_SECRET}"
fi

echo "==> dbt ${COMMAND} | env=${ENV} schema=${SCHEMA} threads=${THREADS}"
echo "==> image: ${IMAGE}"

kubectl apply -f - <<MANIFEST
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
  labels: { app: dbt, env: "${ENV}", dbt-command: "${COMMAND}" }
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 0
  template:
    metadata:
      labels: { app: dbt, job-name: ${JOB_NAME} }
    spec:
      restartPolicy: Never${PULL_SECRET_BLOCK}
      containers:
        - name: dbt
          image: ${IMAGE}
          args: ${ARGS_JSON}
          env:
            - { name: DBT_TARGET,  value: "${ENV}" }
            - { name: DBT_SCHEMA,  value: "${SCHEMA}" }
            - { name: DBT_THREADS, value: "${THREADS}" }
          resources:
            requests: { cpu: "200m", memory: "512Mi" }
            limits:   { cpu: "500m", memory: "1Gi" }
MANIFEST

echo "==> Job created. Waiting for pod..."
kubectl wait --for=condition=ready pod -l "job-name=${JOB_NAME}" -n "${NAMESPACE}" --timeout=120s 2>/dev/null || true

echo "==> Streaming logs:"
kubectl logs -n "${NAMESPACE}" -l "job-name=${JOB_NAME}" -f 2>/dev/null || true

if kubectl wait --for=condition=complete "job/${JOB_NAME}" -n "${NAMESPACE}" --timeout=600s 2>/dev/null; then
  echo "==> ✓ dbt ${COMMAND} SUCCEEDED"
else
  echo "==> ✗ dbt ${COMMAND} FAILED"
  echo "    Debug: kubectl logs -n ${NAMESPACE} -l job-name=${JOB_NAME}"
  exit 1
fi

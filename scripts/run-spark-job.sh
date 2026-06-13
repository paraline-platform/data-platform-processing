#!/usr/bin/env bash
# ============================================================
# RUN-SPARK-JOB.SH — Entry point để deploy Spark jobs
# ============================================================
# Usage:
#   ./scripts/run-spark-job.sh <env> <profile> <job-name> [action]
#
# Arguments:
#   env      : dev | uat | prod
#   profile  : small | medium | large | xlarge
#   job-name : tên file trong spark-jobs/ (không có .yaml)
#   action   : apply (default) | delete | template | status | logs
#
# Examples:
#   ./scripts/run-spark-job.sh dev small spark-pi
#   ./scripts/run-spark-job.sh dev small spark-pi template   # xem YAML trước
#   ./scripts/run-spark-job.sh dev small spark-pi delete
#   ./scripts/run-spark-job.sh dev small spark-pi status
#   ./scripts/run-spark-job.sh dev small spark-pi logs
# ============================================================

set -euo pipefail

# --- Args ---
ENV=${1:?$'Usage: ./scripts/run-spark-job.sh <env> <profile> <job-name> [action]\nExample: ./scripts/run-spark-job.sh dev small spark-pi'}
PROFILE=${2:?$'Missing profile. Use: small | medium | large | xlarge'}
JOB_NAME=${3:?$'Missing job-name. Files available in spark-jobs/'}
ACTION=${4:-apply}

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
# INFRA_DIR: platform/ = submodule root (data-platform-infra), platform config lives inside platform/
INFRA_DIR="$ROOT_DIR/platform/platform"
CHART_DIR="$INFRA_DIR/charts/spark-job"
PROFILES_FILE="$INFRA_DIR/spark-profiles/${ENV}.yaml"
JOB_FILE="$ROOT_DIR/spark-jobs/${JOB_NAME}.yaml"

# --- Validate ---
if [[ ! -f "$PROFILES_FILE" ]]; then
  echo "ERROR: Profiles file not found: $PROFILES_FILE"
  echo "       Available envs: $(ls "$INFRA_DIR/spark-profiles/" | sed 's/.yaml//' | tr '\n' ', ')"
  exit 1
fi
if [[ ! -f "$JOB_FILE" ]]; then
  echo "ERROR: Job file not found: $JOB_FILE"
  echo "       Available jobs: $(ls "$ROOT_DIR/spark-jobs/" | sed 's/.yaml//' | tr '\n' ', ')"
  exit 1
fi

# Validate profile exists in profiles file
if ! grep -q "^  ${PROFILE}:" "$PROFILES_FILE" 2>/dev/null; then
  echo "ERROR: Profile '${PROFILE}' not found in ${PROFILES_FILE}"
  echo "       Available profiles: small, medium, large, xlarge"
  exit 1
fi

# --- Helper: build helm template command ---
helm_template() {
  helm template "$JOB_NAME" "$CHART_DIR" \
    --values "$PROFILES_FILE" \
    --values "$JOB_FILE" \
    --set "profile=${PROFILE}"
}

NAMESPACE="data-processing"

# --- Actions ---
case "$ACTION" in
  apply)
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  Deploying Spark Job                                     ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║  Job     : $JOB_NAME"
    echo "║  Env     : $ENV"
    echo "║  Profile : $PROFILE"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    helm_template | kubectl apply -f -

    echo ""
    echo "==> Job submitted. Waiting for driver pod..."
    sleep 3

    # Show status
    kubectl get sparkapplication "$JOB_NAME" -n "$NAMESPACE" 2>/dev/null || true
    echo ""
    echo "==> Theo dõi kết quả:"
    echo "    kubectl get sparkapplication $JOB_NAME -n $NAMESPACE -w"
    echo "    kubectl logs -n $NAMESPACE ${JOB_NAME}-driver -f"
    echo ""
    echo "==> Xóa sau khi test:"
    echo "    ./scripts/run-spark-job.sh $ENV $PROFILE $JOB_NAME delete"
    ;;

  delete)
    echo "==> Deleting SparkApplication: $JOB_NAME"
    kubectl delete sparkapplication "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found
    echo "==> Done."
    ;;

  template)
    echo "# ============================================================"
    echo "# Rendered YAML: $JOB_NAME [env=$ENV, profile=$PROFILE]"
    echo "# ============================================================"
    helm_template
    ;;

  status)
    echo "==> SparkApplication:"
    kubectl get sparkapplication "$JOB_NAME" -n "$NAMESPACE"
    echo ""
    echo "==> Driver Pod:"
    kubectl get pod "${JOB_NAME}-driver" -n "$NAMESPACE" 2>/dev/null || echo "(driver not found yet)"
    echo ""
    echo "==> Executor Pods:"
    kubectl get pods -n "$NAMESPACE" -l "spark-role=executor" 2>/dev/null || true
    ;;

  logs)
    echo "==> Streaming logs từ driver pod: ${JOB_NAME}-driver"
    kubectl logs -n "$NAMESPACE" "${JOB_NAME}-driver" -f
    ;;

  *)
    echo "ERROR: Unknown action '$ACTION'"
    echo "       Valid actions: apply | delete | template | status | logs"
    exit 1
    ;;
esac

#!/usr/bin/env bash
# ============================================================
# SYNC-PLATFORM.SH — Đồng bộ submodule platform với infra
# ============================================================
# Dùng khi: muốn pull thủ công infra changes mới nhất vào
# data-platform-processing mà không cần chờ CI tự động.
#
# Cơ chế:
#   - Đọc branch hiện tại của processing repo
#   - Fetch + checkout đúng branch đó trong submodule platform/
#   - Pull latest commit từ infra
#
# Usage:
#   ./scripts/sync-platform.sh           # sync với infra branch tương ứng
#   ./scripts/sync-platform.sh stg       # override: sync với infra stg
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Xác định branch cần track trong infra
TARGET_BRANCH="${1:-}"
if [ -z "$TARGET_BRANCH" ]; then
  # Lấy branch hiện tại của processing repo
  CURRENT_BRANCH=$(git -C "$REPO_ROOT" branch --show-current)
  TARGET_BRANCH="$CURRENT_BRANCH"
  echo "[sync-platform] Auto-detected branch: ${TARGET_BRANCH}"
else
  echo "[sync-platform] Using specified branch: ${TARGET_BRANCH}"
fi

# Validate: chỉ cho phép stg/uat/prd (các env branches)
case "$TARGET_BRANCH" in
  stg|uat|prd) ;;
  *)
    echo "[sync-platform] ⚠️  Branch '${TARGET_BRANCH}' không phải env branch (stg/uat/prd)"
    echo "                    Tiếp tục nhưng hãy đảm bảo infra có branch này."
    ;;
esac

PLATFORM_DIR="${REPO_ROOT}/platform"

# Đảm bảo submodule đã được init
if [ ! -f "${PLATFORM_DIR}/helmfile.yaml.gotmpl" ]; then
  echo "[sync-platform] Initializing submodule..."
  git -C "$REPO_ROOT" submodule update --init platform
fi

echo "[sync-platform] Fetching infra/${TARGET_BRANCH}..."
git -C "$PLATFORM_DIR" fetch origin "$TARGET_BRANCH"
git -C "$PLATFORM_DIR" checkout "$TARGET_BRANCH"
git -C "$PLATFORM_DIR" pull origin "$TARGET_BRANCH"

NEW_SHA=$(git -C "$PLATFORM_DIR" rev-parse --short HEAD)
echo "[sync-platform] ✓ platform submodule → infra/${TARGET_BRANCH}@${NEW_SHA}"

# Kiểm tra xem có thay đổi không
if git -C "$REPO_ROOT" diff --quiet platform; then
  echo "[sync-platform] ✓ Không có thay đổi — đã up-to-date"
else
  echo "[sync-platform] Submodule pointer đã thay đổi. Để commit:"
  echo "  git add platform"
  echo "  git commit -m 'chore(submodule): bump platform → infra/${TARGET_BRANCH}@${NEW_SHA}'"
fi

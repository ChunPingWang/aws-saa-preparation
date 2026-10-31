#!/usr/bin/env bash
# =============================================================
# 共用環境變數：每支 Lab 腳本開頭都會 source 這個檔案
# 使用方式：source scripts/00-env.sh
# 建議在 AWS CloudShell (us-east-1) 執行，免安裝 CLI、免設定金鑰
# =============================================================
set -euo pipefail

export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_PAGER=""

# 所有資源都以這個前綴命名，方便辨識與清理
export PREFIX="${PREFIX:-saa}"

# 帳號 ID（自動取得，不需手動填）
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# S3 Bucket 名稱必須全球唯一，預設加上帳號 ID 與日期
export BUCKET="${BUCKET:-${PREFIX}-lab-site-${ACCOUNT_ID}-$(date +%Y%m%d)}"

# 狀態檔：記錄每個 Lab 建立的資源 ID，供後續 Lab 與清理腳本使用
export STATE_FILE="${STATE_FILE:-$HOME/.saa-lab-state}"
touch "$STATE_FILE"

save_state() {   # save_state KEY VALUE
  local key="$1" val="$2"
  grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" || true
  echo "${key}=${val}" >> "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}
load_state() {   # 將狀態檔載入成環境變數
  # shellcheck disable=SC1090
  set -a; source "$STATE_FILE"; set +a
}
load_state

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

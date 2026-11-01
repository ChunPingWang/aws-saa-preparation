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

# 產生符合 IAM 預設密碼政策的隨機密碼：
#   預設政策 = 至少 8 字元，且大寫/小寫/數字/符號四類中至少三類。
#   這裡產生 20 字元英數（保證含大寫、小寫、數字）再補 1 個符號 → 四類都有、共 21 字元，
#   即使帳號改成「至少 14 字元、四類皆要」的自訂政策也能通過。
gen_password() {
  local p symbols='!@#%^*_+-=' i
  while :; do
    p="$(openssl rand -base64 33 | tr -d '\n=/+' | cut -c1-20)"
    [[ ${#p} -eq 20 && $p =~ [A-Z] && $p =~ [a-z] && $p =~ [0-9] ]] && break
  done
  i=$(( $(openssl rand 1 | od -An -tu1) % ${#symbols} ))
  printf '%s%s' "$p" "${symbols:$i:1}"
}

# 主控台登入 URL：有帳號別名時另外列出別名網址
console_signin_urls() {
  local alias_name
  echo "https://${ACCOUNT_ID}.signin.aws.amazon.com/console"
  alias_name="$(aws iam list-account-aliases --query 'AccountAliases[0]' --output text 2>/dev/null || true)"
  if [ -n "$alias_name" ] && [ "$alias_name" != "None" ]; then
    echo "https://${alias_name}.signin.aws.amazon.com/console"
  fi
}

# 印出一次性的登入資訊（密碼只出現這一次，不寫入任何檔案）
print_console_login() {   # print_console_login USER PASSWORD
  local url
  printf '\n\033[1;33m%s\033[0m\n' "================ 只會顯示這一次，請立刻存到密碼管理器 ================"
  for url in $(console_signin_urls); do echo "登入 URL     : $url"; done
  echo "帳號 ID      : ${ACCOUNT_ID}"
  echo "IAM 使用者名稱: $1"
  echo "初始密碼     : $2"
  echo "首次登入會要求輸入「舊密碼（上面這組）＋新密碼兩次」。"
  printf '\033[1;33m%s\033[0m\n' "======================================================================"
  echo "遺失時請由管理員重設：aws iam update-login-profile --user-name $1 --password '<新密碼>' --password-reset-required"
}

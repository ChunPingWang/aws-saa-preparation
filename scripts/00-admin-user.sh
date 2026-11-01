#!/usr/bin/env bash
# =============================================================
# Lab 0：建立管理員群組 saa-admins 與 IAM 使用者 saa-admin
#   - 群組附加 AWS 受管政策 AdministratorAccess
#   - 使用者有「主控台密碼」（用 openssl rand 產生的隨機強密碼），
#     並設定 --password-reset-required：第一次登入必須自己改密碼
#   - 不建立任何存取金鑰（Access Key）
#
# 執行身分：root 使用者（帳號剛開好、還沒有任何管理員時）或既有的管理員
# 建議環境：AWS CloudShell（us-east-1）。root 也能開 CloudShell。
# 密碼只會印出一次，不會寫入狀態檔；請立刻存到密碼管理器。
# =============================================================
source "$(dirname "$0")/00-env.sh"

ADMIN_GROUP="${ADMIN_GROUP:-${PREFIX}-admins}"
ADMIN_USER="${ADMIN_USER:-${PREFIX}-admin}"

CALLER_ARN="$(aws sts get-caller-identity --query Arn --output text)"
log "目前執行身分：$CALLER_ARN"
case "$CALLER_ARN" in
  *":root") echo "以 root 執行。完成後請登出 root，之後一律用 IAM 使用者 ${ADMIN_USER} 登入。" ;;
  *) echo "以 IAM 身分執行（需要 iam:* 權限，例如 AdministratorAccess）。" ;;
esac

log "1. 建立群組 ${ADMIN_GROUP} 並附加 AdministratorAccess"
if aws iam get-group --group-name "$ADMIN_GROUP" >/dev/null 2>&1; then
  echo "群組已存在，略過建立"
else
  aws iam create-group --group-name "$ADMIN_GROUP" >/dev/null
fi
aws iam attach-group-policy --group-name "$ADMIN_GROUP" \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

log "2. 建立使用者 ${ADMIN_USER} 並加入群組（權限掛在群組，不直接掛在使用者）"
if aws iam get-user --user-name "$ADMIN_USER" >/dev/null 2>&1; then
  echo "使用者已存在，略過建立"
else
  aws iam create-user --user-name "$ADMIN_USER" >/dev/null
fi
aws iam add-user-to-group --user-name "$ADMIN_USER" --group-name "$ADMIN_GROUP"

log "3. 附加 IAMUserChangePassword（等同主控台勾選『人員必須在下次登入時建立新的密碼』）"
aws iam attach-user-policy --user-name "$ADMIN_USER" \
  --policy-arn arn:aws:iam::aws:policy/IAMUserChangePassword

log "4. 建立主控台密碼（login profile），首次登入必須變更"
if aws iam get-login-profile --user-name "$ADMIN_USER" >/dev/null 2>&1; then
  echo "此使用者已經有主控台密碼，不覆寫。"
  echo "若忘記密碼，請以 root 或其他管理員重設："
  echo "  aws iam update-login-profile --user-name $ADMIN_USER --password '<新密碼>' --password-reset-required"
else
  PW="$(gen_password)"
  aws iam create-login-profile --user-name "$ADMIN_USER" --password "$PW" --password-reset-required >/dev/null
  print_console_login "$ADMIN_USER" "$PW"
  unset PW
fi

log "5. 驗證（不含任何機密）"
aws iam list-attached-group-policies --group-name "$ADMIN_GROUP" --output table
aws iam get-group --group-name "$ADMIN_GROUP" --query 'Users[].UserName' --output table
aws iam get-login-profile --user-name "$ADMIN_USER" \
  --query 'LoginProfile.[UserName,PasswordResetRequired,CreateDate]' --output table
aws iam list-access-keys --user-name "$ADMIN_USER" --query 'length(AccessKeyMetadata)' --output text \
  | xargs -I{} echo "存取金鑰數量：{}（應為 0）"

cat <<'TXT'

下一步：
  1. 登出 root，開啟上面的「登入 URL」，用 IAM 使用者登入並設定新密碼。
  2. 登入後到 IAM → 使用者 → saa-admin → 安全憑證 → 指派 MFA 裝置。
  3. 之後的 Lab 1–12 都用 saa-admin 操作；root 只留給帳號層級的必要工作。
TXT

#!/usr/bin/env bash
# Lab 12：KMS 客戶受管金鑰（加解密）+ Secrets Manager（檢視 RDS 受管密碼，不印出明文）
source "$(dirname "$0")/00-env.sh"

log "建立對稱 KMS 金鑰與別名 alias/${PREFIX}-lab-key，並啟用每年自動輪換"
# CLI 不指定 --policy 時使用「預設金鑰政策」（只有 Enable IAM User Permissions 一段），
# 由 IAM 政策決定誰能用；主控台精靈則另外把 saa-admin 寫成金鑰管理員與使用者。
KEY_ID=$(aws kms create-key --description "SAA lab customer managed key" --query KeyMetadata.KeyId --output text)
aws kms create-alias --alias-name "alias/${PREFIX}-lab-key" --target-key-id "$KEY_ID"
aws kms enable-key-rotation --key-id "$KEY_ID"
save_state KEY_ID "$KEY_ID"

log "加密 → 解密（示範資料）"
echo 'card-token: tok_demo_4242' > /tmp/plain.txt
aws kms encrypt --key-id "alias/${PREFIX}-lab-key" --plaintext fileb:///tmp/plain.txt \
  --query CiphertextBlob --output text | base64 -d > /tmp/cipher.bin
echo "Ciphertext bytes: $(wc -c < /tmp/cipher.bin)"
aws kms decrypt --ciphertext-blob fileb:///tmp/cipher.bin --query Plaintext --output text | base64 -d

log "Secrets Manager：RDS 以 --manage-master-user-password 自動建立的密碼（只看中繼資料）"
aws secretsmanager list-secrets --query 'SecretList[?starts_with(Name, `rds!`)].[Name,RotationEnabled,Description]' --output table

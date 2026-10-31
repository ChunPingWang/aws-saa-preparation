#!/usr/bin/env bash
# Lab 5：S3 Bucket（封鎖公開存取、版本控制、SSE-S3、生命週期）
source "$(dirname "$0")/00-env.sh"
ROOT="$(dirname "$0")/.."

log "建立 Bucket：$BUCKET"
if [ "$AWS_REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$BUCKET" >/dev/null
else
  aws s3api create-bucket --bucket "$BUCKET" --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
fi
save_state BUCKET "$BUCKET"

log "封鎖所有公開存取（新 Bucket 預設即開啟，這裡明確設定）"
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

log "啟用版本控制"
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled

log "預設加密 SSE-S3 + Bucket Key"
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

log "上傳測試資料（v1），再覆寫 index.html（v2）以產生兩個版本"
aws s3 cp "$ROOT/test-data/site/index.html" "s3://$BUCKET/index.html"
aws s3 cp "$ROOT/test-data/site/error.html" "s3://$BUCKET/error.html"
aws s3 cp "$ROOT/test-data/site/orders.csv" "s3://$BUCKET/orders.csv"
aws s3 cp "$ROOT/test-data/site/index-v2.html" "s3://$BUCKET/index.html"
aws s3api list-object-versions --bucket "$BUCKET" --prefix index.html \
  --query 'Versions[].[Key,VersionId,IsLatest,LastModified]' --output table

log "生命週期：30 天→Standard-IA、90 天→Glacier Flexible Retrieval、非目前版本 30 天後刪除"
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" \
  --lifecycle-configuration "file://$ROOT/policies/s3-lifecycle.json"
aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET" --output json

log "（選做）S3 Select / 查詢：用 CLI 下載 CSV 並計算總金額"
aws s3 cp "s3://$BUCKET/orders.csv" - | awk -F, 'NR>1{s+=$4} END{print "Total amount =", s}'

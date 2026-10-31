#!/usr/bin/env bash
# Lab 9：CloudFront + Origin Access Control（OAC）提供私有 S3 內容
source "$(dirname "$0")/00-env.sh"
ROOT="$(dirname "$0")/.."

log "建立 OAC（SigV4 簽章，取代舊的 OAI）"
OAC_ID=$(aws cloudfront create-origin-access-control --origin-access-control-config \
  "Name=${PREFIX}-site-oac,Description=SAA lab OAC,SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3" \
  --query OriginAccessControl.Id --output text)
save_state OAC_ID "$OAC_ID"

log "建立 Distribution（快取政策：Managed-CachingOptimized，強制 HTTPS）"
cat > /tmp/cf.json <<JSON
{
  "CallerReference": "${PREFIX}-$(date +%s)",
  "Comment": "${PREFIX}-lab-site",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "s3-${BUCKET}",
      "DomainName": "${BUCKET}.s3.${AWS_REGION}.amazonaws.com",
      "OriginAccessControlId": "${OAC_ID}",
      "S3OriginConfig": { "OriginAccessIdentity": "" }
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-${BUCKET}",
    "ViewerProtocolPolicy": "redirect-to-https",
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "Compress": true
  },
  "PriceClass": "PriceClass_100"
}
JSON
read -r DIST_ID DIST_DOMAIN < <(aws cloudfront create-distribution --distribution-config file:///tmp/cf.json \
  --query 'Distribution.[Id,DomainName]' --output text)
save_state DIST_ID "$DIST_ID"; save_state DIST_DOMAIN "$DIST_DOMAIN"

log "Bucket Policy：只允許這個 Distribution 讀取（AWS:SourceArn 條件）"
sed -e "s/__BUCKET__/$BUCKET/" -e "s/__ACCOUNT_ID__/$ACCOUNT_ID/" -e "s/__DISTRIBUTION_ID__/$DIST_ID/" \
  "$ROOT/policies/s3-oac-bucket-policy.template.json" > /tmp/bucket-policy.json
aws s3api put-bucket-policy --bucket "$BUCKET" --policy file:///tmp/bucket-policy.json

log "等待部署完成（約 3–10 分鐘）"
aws cloudfront wait distribution-deployed --id "$DIST_ID"
echo "CloudFront：$(curl -s "https://$DIST_DOMAIN/")"
echo "直接存取 S3（應為 403）：$(curl -s -o /dev/null -w '%{http_code}' "https://${BUCKET}.s3.${AWS_REGION}.amazonaws.com/index.html")"

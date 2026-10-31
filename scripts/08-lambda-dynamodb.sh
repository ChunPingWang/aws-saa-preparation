#!/usr/bin/env bash
# Lab 8：DynamoDB（On-Demand）+ Lambda（Python）+ 最小權限 IAM 角色
source "$(dirname "$0")/00-env.sh"
ROOT="$(dirname "$0")/.."

log "建立 DynamoDB 資料表 ${PREFIX}-orders（PK: order_id，隨需容量）"
aws dynamodb create-table --table-name "${PREFIX}-orders" \
  --attribute-definitions AttributeName=order_id,AttributeType=S \
  --key-schema AttributeName=order_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST >/dev/null
aws dynamodb wait table-exists --table-name "${PREFIX}-orders"

log "建立 Lambda 執行角色（基本日誌權限 + 只允許 PutItem/GetItem）"
ROLE_NAME="${PREFIX}-order-api-role"
ROLE_ARN=$(aws iam create-role --role-name "$ROLE_NAME" \
  --assume-role-policy-document "file://$ROOT/policies/lambda-trust-policy.json" \
  --query Role.Arn --output text)
aws iam attach-role-policy --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
sed "s/saa-orders/${PREFIX}-orders/" "$ROOT/policies/lambda-dynamodb-policy.json" > /tmp/ddb-policy.json
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "${PREFIX}-orders-rw" \
  --policy-document file:///tmp/ddb-policy.json
save_state LAMBDA_ROLE "$ROLE_NAME"
sleep 10   # 等待 IAM 角色傳播

log "打包並建立 Lambda 函式 ${PREFIX}-order-api"
(cd "$ROOT/lambda" && zip -q /tmp/fn.zip lambda_function.py)
aws lambda create-function --function-name "${PREFIX}-order-api" \
  --runtime python3.13 --handler lambda_function.lambda_handler \
  --role "$ROLE_ARN" --zip-file fileb:///tmp/fn.zip \
  --environment "Variables={TABLE_NAME=${PREFIX}-orders}" --timeout 10 >/dev/null
aws lambda wait function-active-v2 --function-name "${PREFIX}-order-api"

log "呼叫函式：建立 → 查詢 → 查詢不存在的訂單"
for ev in create-order get-order get-missing-order; do
  aws lambda invoke --function-name "${PREFIX}-order-api" --cli-binary-format raw-in-base64-out \
    --payload "file://$ROOT/lambda/events/$ev.json" "/tmp/$ev.out" >/dev/null
  echo "$ev => $(cat /tmp/$ev.out)"
done
aws dynamodb scan --table-name "${PREFIX}-orders" --query 'Items[].[order_id.S,customer.S,amount.N]' --output table

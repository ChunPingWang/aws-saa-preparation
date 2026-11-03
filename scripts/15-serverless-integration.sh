#!/usr/bin/env bash
# Lab 15：API Gateway REST API → Lambda（Proxy）＋ EventBridge 規則 → Step Functions
source "$(dirname "$0")/00-env.sh"
ROOT="$(dirname "$0")/.."

log "Lambda ${PREFIX}-hello：執行角色（只寫 Logs）＋ Python 3.14"
ROLE=${PREFIX}-hello-role
aws iam create-role --role-name "$ROLE" --assume-role-policy-document "file://$ROOT/policies/lambda-trust-policy.json" >/dev/null
aws iam attach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
sleep 10
(cd "$ROOT/lambda/hello" && zip -q /tmp/hello.zip lambda_function.py)
FN_ARN=$(aws lambda create-function --function-name "${PREFIX}-hello" --runtime python3.14 \
  --role "arn:aws:iam::${ACCOUNT_ID}:role/$ROLE" --handler lambda_function.lambda_handler \
  --zip-file fileb:///tmp/hello.zip --query FunctionArn --output text)
aws lambda wait function-active-v2 --function-name "${PREFIX}-hello"

log "REST API ${PREFIX}-hello-api（Regional）：/hello GET → Lambda Proxy"
API=$(aws apigateway create-rest-api --name "${PREFIX}-hello-api" --endpoint-configuration types=REGIONAL \
  --query id --output text)
ROOT_ID=$(aws apigateway get-resources --rest-api-id "$API" --query 'items[?path==`/`].id' --output text)
RES=$(aws apigateway create-resource --rest-api-id "$API" --parent-id "$ROOT_ID" --path-part hello --query id --output text)
aws apigateway put-method --rest-api-id "$API" --resource-id "$RES" --http-method GET --authorization-type NONE >/dev/null
aws apigateway put-integration --rest-api-id "$API" --resource-id "$RES" --http-method GET \
  --type AWS_PROXY --integration-http-method POST \
  --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${FN_ARN}/invocations" >/dev/null
# 主控台會自動加這段資源型政策；CLI 要自己加
aws lambda add-permission --function-name "${PREFIX}-hello" --statement-id apigw-invoke \
  --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${ACCOUNT_ID}:${API}/*/GET/hello" >/dev/null
aws apigateway create-deployment --rest-api-id "$API" --stage-name dev --description "first deployment" >/dev/null
save_state API_ID "$API"
URL="https://${API}.execute-api.${AWS_REGION}.amazonaws.com/dev"
sleep 5
curl -s "$URL/hello?name=Rex"; echo
curl -s -o /dev/null -w 'GET /nothing -> HTTP %{http_code}\n' "$URL/nothing"

log "Step Functions ${PREFIX}-order-flow（標準）"
SFN_ROLE=${PREFIX}-order-flow-role
aws iam create-role --role-name "$SFN_ROLE" --assume-role-policy-document \
 '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
sleep 10
SM=$(aws stepfunctions create-state-machine --name "${PREFIX}-order-flow" --type STANDARD \
  --definition "file://$ROOT/stepfunctions/order-flow.asl.json" \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/$SFN_ROLE" --query stateMachineArn --output text)
save_state SM_ARN "$SM"

log "EventBridge 規則 ${PREFIX}-order-created-rule → 狀態機"
EB_ROLE=${PREFIX}-eventbridge-sfn-role
aws iam create-role --role-name "$EB_ROLE" --assume-role-policy-document \
 '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"events.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
aws iam put-role-policy --role-name "$EB_ROLE" --policy-name start-execution --policy-document \
 "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"states:StartExecution\",\"Resource\":\"$SM\"}]}"
sleep 10
aws events put-rule --name "${PREFIX}-order-created-rule" \
  --event-pattern '{"source":["saa.orders"],"detail-type":["OrderCreated"]}' >/dev/null
aws events put-targets --rule "${PREFIX}-order-created-rule" \
  --targets "Id=sfn,Arn=$SM,RoleArn=arn:aws:iam::${ACCOUNT_ID}:role/$EB_ROLE" >/dev/null

log "送 3 個事件：A2001(250)、A2002(45)、OrderShipped（應被過濾）"
aws events put-events --entries '[
 {"Source":"saa.orders","DetailType":"OrderCreated","Detail":"{\"order_id\":\"A2001\",\"amount\":250}"},
 {"Source":"saa.orders","DetailType":"OrderCreated","Detail":"{\"order_id\":\"A2002\",\"amount\":45}"},
 {"Source":"saa.orders","DetailType":"OrderShipped","Detail":"{\"order_id\":\"A2001\"}"}]' --query FailedEntryCount
sleep 20
aws stepfunctions list-executions --state-machine-arn "$SM" --query 'executions[].[name,status]' --output table

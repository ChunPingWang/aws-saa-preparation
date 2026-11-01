#!/usr/bin/env bash
# Lab 11：SNS → SQS 扇出（Fan-out）解耦
source "$(dirname "$0")/00-env.sh"

log "建立 SQS 標準佇列 ${PREFIX}-order-queue"
Q_URL=$(aws sqs create-queue --queue-name "${PREFIX}-order-queue" --query QueueUrl --output text)
Q_ARN=$(aws sqs get-queue-attributes --queue-url "$Q_URL" --attribute-names QueueArn \
  --query Attributes.QueueArn --output text)
save_state Q_URL "$Q_URL"

log "佇列存取政策：允許 SNS Topic 傳送訊息"
# 主控台從 SQS 端「訂閱 Amazon SNS 主題」會自動加一段 Principal "*" + aws:SourceArn 條件；
# 這裡用更嚴謹的 Principal = sns.amazonaws.com，效果相同。
POLICY=$(cat <<JSON
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"sns.amazonaws.com"},
"Action":"sqs:SendMessage","Resource":"$Q_ARN","Condition":{"ArnEquals":{"aws:SourceArn":"$TOPIC_ARN"}}}]}
JSON
)
aws sqs set-queue-attributes --queue-url "$Q_URL" \
  --attributes "{\"Policy\":$(jq -Rs . <<<"$POLICY")}"

log "訂閱：SNS Topic → SQS"
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs --notification-endpoint "$Q_ARN" >/dev/null

log "發佈訊息並從佇列接收"
aws sns publish --topic-arn "$TOPIC_ARN" --subject OrderCreated \
  --message '{"order_id":"A1003","amount":95}' --query MessageId --output text
aws sqs receive-message --queue-url "$Q_URL" --max-number-of-messages 10 --wait-time-seconds 5 --output json \
  | jq -r '.Messages[].Body | fromjson | "\(.Type) | \(.Subject) | \(.Message)"'

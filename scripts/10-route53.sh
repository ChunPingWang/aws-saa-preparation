#!/usr/bin/env bash
# Lab 10：Route 53 私有託管區域 + Alias 記錄指向 ALB，在 VPC 內解析
source "$(dirname "$0")/00-env.sh"

log "建立私有託管區域 saa.internal 並關聯 ${PREFIX}-lab-vpc"
ZONE_ID=$(aws route53 create-hosted-zone --name saa.internal \
  --caller-reference "${PREFIX}-$(date +%s)" \
  --vpc "VPCRegion=${AWS_REGION},VPCId=${VPC_ID}" \
  --hosted-zone-config "Comment=SAA lab private zone,PrivateZone=true" \
  --query HostedZone.Id --output text)
save_state ZONE_ID "$ZONE_ID"

log "建立 Alias A 記錄 app.saa.internal → ALB"
read -r ALB_ZONE ALB_DNS_NAME < <(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].[CanonicalHostedZoneId,DNSName]' --output text)
cat > /tmp/r53.json <<JSON
{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{
  "Name":"app.saa.internal","Type":"A",
  "AliasTarget":{"HostedZoneId":"$ALB_ZONE","DNSName":"dualstack.$ALB_DNS_NAME","EvaluateTargetHealth":true}}}]}
JSON
aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch file:///tmp/r53.json >/dev/null

log "從 VPC 內的 EC2 驗證（透過 SSM Run Command，不需登入）"
CMD_ID=$(aws ssm send-command --instance-ids "$WEB_ID" --document-name AWS-RunShellScript \
  --parameters 'commands=["getent hosts app.saa.internal","curl -s http://app.saa.internal/"]' \
  --query Command.CommandId --output text)
sleep 8
aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$WEB_ID" \
  --query StandardOutputContent --output text

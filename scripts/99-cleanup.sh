#!/usr/bin/env bash
# 清除所有 Lab 資源（依相依順序）。可重複執行；已刪除的資源會略過。
# ⚠️ 會永久刪除資料（S3 物件、RDS、DynamoDB），執行前請確認。
source "$(dirname "$0")/00-env.sh"
set +e
read -r -p "確定要刪除所有 ${PREFIX} Lab 資源？輸入 yes 繼續：" ans
[ "$ans" = "yes" ] || { echo "已取消"; exit 0; }

log "1. CloudFront：先停用，部署完成後刪除，再刪 OAC"
if [ -n "${DIST_ID:-}" ]; then
  aws cloudfront get-distribution-config --id "$DIST_ID" > /tmp/cf-cur.json
  ETAG=$(jq -r .ETag /tmp/cf-cur.json)
  jq '.DistributionConfig.Enabled=false | .DistributionConfig' /tmp/cf-cur.json > /tmp/cf-off.json
  aws cloudfront update-distribution --id "$DIST_ID" --if-match "$ETAG" --distribution-config file:///tmp/cf-off.json >/dev/null
  echo "等待停用部署完成..."; aws cloudfront wait distribution-deployed --id "$DIST_ID"
  ETAG=$(aws cloudfront get-distribution --id "$DIST_ID" --query ETag --output text)
  aws cloudfront delete-distribution --id "$DIST_ID" --if-match "$ETAG"
fi
if [ -n "${OAC_ID:-}" ]; then
  ETAG=$(aws cloudfront get-origin-access-control --id "$OAC_ID" --query ETag --output text)
  aws cloudfront delete-origin-access-control --id "$OAC_ID" --if-match "$ETAG"
fi

log "2. 運算層：ASG、ALB、Target Group、Launch Template、EC2"
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "${PREFIX}-app-asg" --force-delete
[ -n "${ALB_ARN:-}" ] && aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
[ -n "${WEB_ID:-}" ]  && aws ec2 terminate-instances --instance-ids "$WEB_ID" >/dev/null
aws ec2 delete-launch-template --launch-template-name "${PREFIX}-app-lt" >/dev/null
sleep 30
[ -n "${TG_ARN:-}" ] && aws elbv2 delete-target-group --target-group-arn "$TG_ARN"

log "3. 資料層：RDS、DB Subnet Group、DynamoDB"
aws rds delete-db-instance --db-instance-identifier "${PREFIX}-lab-mysql" \
  --skip-final-snapshot --delete-automated-backups >/dev/null
aws dynamodb delete-table --table-name "${PREFIX}-orders" >/dev/null

log "4. 無伺服器與整合：Lambda、Log Group、Alarm、SNS、SQS"
aws lambda delete-function --function-name "${PREFIX}-order-api"
aws logs delete-log-group --log-group-name "/aws/lambda/${PREFIX}-order-api"
aws cloudwatch delete-alarms --alarm-names "${PREFIX}-asg-high-cpu"
[ -n "${Q_URL:-}" ] && aws sqs delete-queue --queue-url "$Q_URL"
[ -n "${TOPIC_ARN:-}" ] && aws sns delete-topic --topic-arn "$TOPIC_ARN"

log "5. Route 53：刪除 Alias 記錄與私有託管區域"
if [ -n "${ZONE_ID:-}" ]; then
  aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
    --query "ResourceRecordSets[?Type=='A']" > /tmp/a.json
  if [ "$(jq length /tmp/a.json)" -gt 0 ]; then
    jq '{Changes:[.[]|{Action:"DELETE",ResourceRecordSet:.}]}' /tmp/a.json > /tmp/del.json
    aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch file:///tmp/del.json >/dev/null
  fi
  aws route53 delete-hosted-zone --id "$ZONE_ID" >/dev/null
fi

log "6. KMS：排程刪除（最短 7 天，期間可取消）"
[ -n "${KEY_ID:-}" ] && aws kms delete-alias --alias-name "alias/${PREFIX}-lab-key" && \
  aws kms schedule-key-deletion --key-id "$KEY_ID" --pending-window-in-days 7 >/dev/null

log "7. S3：刪除所有版本與刪除標記，再刪 Bucket"
if [ -n "${BUCKET:-}" ]; then
  aws s3api list-object-versions --bucket "$BUCKET" --output json \
    | jq '{Objects: ([.Versions[]?, .DeleteMarkers[]?] | map({Key, VersionId}))}' > /tmp/objs.json
  [ "$(jq '.Objects|length' /tmp/objs.json)" -gt 0 ] && \
    aws s3api delete-objects --bucket "$BUCKET" --delete file:///tmp/objs.json >/dev/null
  aws s3api delete-bucket --bucket "$BUCKET"
fi

log "8. 等待 RDS / EC2 刪除完成，再拆 VPC"
aws rds wait db-instance-deleted --db-instance-identifier "${PREFIX}-lab-mysql"
aws rds delete-db-subnet-group --db-subnet-group-name "${PREFIX}-db-subnets"
IDS=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" \
  "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
[ -n "$IDS" ] && aws ec2 terminate-instances --instance-ids $IDS >/dev/null && \
  aws ec2 wait instance-terminated --instance-ids $IDS

log "9. VPC：NAT、EIP、Endpoint、SG、子網路、路由表、IGW、VPC"
[ -n "${NAT_ID:-}" ] && aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" >/dev/null && \
  aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID"
[ -n "${EIP_ALLOC:-}" ] && aws ec2 release-address --allocation-id "$EIP_ALLOC"
[ -n "${VPCE_ID:-}" ] && aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$VPCE_ID" >/dev/null
sleep 20
# 先移除 SG 之間的參照，再刪 SG（ENI 釋放可能需要數分鐘，失敗可稍後重跑）
for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
            --query "SecurityGroups[?GroupName!='default'].GroupId" --output text); do
  perms=$(aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissions' --output json)
  [ "$perms" != "[]" ] && aws ec2 revoke-security-group-ingress --group-id "$sg" --ip-permissions "$perms" >/dev/null
done
for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
            --query "SecurityGroups[?GroupName!='default'].GroupId" --output text); do
  aws ec2 delete-security-group --group-id "$sg"
done
for s in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text); do
  aws ec2 delete-subnet --subnet-id "$s"
done
for r in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" \
           --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text); do
  aws ec2 delete-route-table --route-table-id "$r"
done
for g in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
           --query 'InternetGateways[].InternetGatewayId' --output text); do
  aws ec2 detach-internet-gateway --internet-gateway-id "$g" --vpc-id "$VPC_ID"
  aws ec2 delete-internet-gateway --internet-gateway-id "$g"
done
aws ec2 delete-vpc --vpc-id "$VPC_ID" && echo "VPC 已刪除"

log "10. IAM：Lambda 角色、EC2 角色與 Instance Profile、使用者、群組"
R="${LAMBDA_ROLE:-${PREFIX}-order-api-role}"
aws iam delete-role-policy --role-name "$R" --policy-name "${PREFIX}-orders-rw"
aws iam detach-role-policy --role-name "$R" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam delete-role --role-name "$R"
aws iam remove-role-from-instance-profile --instance-profile-name "${PREFIX}-ec2-ssm-role" --role-name "${PREFIX}-ec2-ssm-role"
aws iam delete-instance-profile --instance-profile-name "${PREFIX}-ec2-ssm-role"
aws iam detach-role-policy --role-name "${PREFIX}-ec2-ssm-role" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role --role-name "${PREFIX}-ec2-ssm-role"
aws iam remove-user-from-group --user-name "${PREFIX}-lab-user" --group-name "${PREFIX}-developers"
aws iam delete-user --user-name "${PREFIX}-lab-user"
for p in AmazonEC2ReadOnlyAccess AmazonS3ReadOnlyAccess; do
  aws iam detach-group-policy --group-name "${PREFIX}-developers" --policy-arn "arn:aws:iam::aws:policy/$p"
done
aws iam delete-group --group-name "${PREFIX}-developers"

log "完成。建議到 Billing → Bills 與 Cost Explorer 隔天再確認一次沒有殘留費用。"
rm -f "$STATE_FILE"

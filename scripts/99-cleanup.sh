#!/usr/bin/env bash
# =============================================================
# 清除所有 Lab 資源（依相依順序）。可重複執行；已刪除的資源會略過（錯誤訊息可忽略）。
# 會永久刪除資料（S3 物件、RDS、DynamoDB），執行前請確認。
#
# - 資源 ID 優先讀 ~/.saa-lab-state（腳本建立時寫入）；
#   用主控台建立的資源沒有狀態檔，這支腳本會改用「名稱 / 標籤」查找。
# - 刻意保留：Lab 0 的 IAM 使用者 saa-admin 與群組 saa-admins
#   （IAM 不計費，下次練習直接登入即可）。
# 執行身分：saa-admin（或其他管理員）
# =============================================================
source "$(dirname "$0")/00-env.sh"
set +e +u
N="${PREFIX}-lab"

read -r -p "確定要刪除所有 ${PREFIX} Lab 資源（保留 ${PREFIX}-admin / ${PREFIX}-admins）？輸入 yes 繼續：" ans
[ "$ans" = "yes" ] || { echo "已取消"; exit 0; }

# ---------- 依名稱補齊 ID（主控台建立的資源） ----------
VPC_ID="${VPC_ID:-$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${N}-vpc" --query 'Vpcs[0].VpcId' --output text)}"
[ "$VPC_ID" = "None" ] && VPC_ID=""
ALB_ARN="${ALB_ARN:-$(aws elbv2 describe-load-balancers --names "${PREFIX}-app-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)}"
TG_ARN="${TG_ARN:-$(aws elbv2 describe-target-groups --names "${PREFIX}-app-tg" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)}"
TOPIC_ARN="${TOPIC_ARN:-$(aws sns list-topics --query "Topics[?ends_with(TopicArn,':${PREFIX}-alerts')].TopicArn | [0]" --output text)}"
[ "$TOPIC_ARN" = "None" ] && TOPIC_ARN=""
Q_URL="${Q_URL:-$(aws sqs get-queue-url --queue-name "${PREFIX}-order-queue" --query QueueUrl --output text 2>/dev/null)}"
ZONE_ID="${ZONE_ID:-$(aws route53 list-hosted-zones-by-name --dns-name saa.internal \
  --query "HostedZones[?Name=='saa.internal.' && Config.PrivateZone].Id | [0]" --output text)}"
[ "$ZONE_ID" = "None" ] && ZONE_ID=""
KEY_ID="${KEY_ID:-$(aws kms describe-key --key-id "alias/${PREFIX}-lab-key" --query KeyMetadata.KeyId --output text 2>/dev/null)}"
# CloudFront：腳本建立的有 DIST_ID；主控台建立的用 Name 標籤（分發名稱）或 Comment 找
if [ -z "${DIST_ID:-}" ]; then
  for id in $(aws cloudfront list-distributions --query 'DistributionList.Items[].Id' --output text 2>/dev/null); do
    [ "$id" = "None" ] && continue
    arn="arn:aws:cloudfront::${ACCOUNT_ID}:distribution/$id"
    nm=$(aws cloudfront list-tags-for-resource --resource "$arn" --query "Tags.Items[?Key=='Name'].Value | [0]" --output text)
    cm=$(aws cloudfront get-distribution-config --id "$id" --query DistributionConfig.Comment --output text)
    if [ "$nm" = "${N}-site" ] || [ "$cm" = "${N}-site" ]; then DIST_ID="$id"; break; fi
  done
fi
# S3：腳本預設名稱 + 主控台自訂名稱（saa-lab-site- 開頭）
BUCKETS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '${N}-site-')].Name" --output text)
echo "將處理：VPC=${VPC_ID:-無} ALB=${ALB_ARN:-無} CloudFront=${DIST_ID:-無} Buckets=${BUCKETS:-無}"

log "1. CloudFront：先停用（部署完成後才能刪除，最後一步再刪）"
OAC_ID="${OAC_ID:-}"
if [ -n "${DIST_ID:-}" ]; then
  aws cloudfront get-distribution-config --id "$DIST_ID" > /tmp/cf-cur.json
  ETAG=$(jq -r .ETag /tmp/cf-cur.json)
  [ -z "$OAC_ID" ] && OAC_ID=$(jq -r '.DistributionConfig.Origins.Items[0].OriginAccessControlId // empty' /tmp/cf-cur.json)
  if [ "$(jq -r .DistributionConfig.Enabled /tmp/cf-cur.json)" = "true" ]; then
    jq '.DistributionConfig.Enabled=false | .DistributionConfig' /tmp/cf-cur.json > /tmp/cf-off.json
    aws cloudfront update-distribution --id "$DIST_ID" --if-match "$ETAG" \
      --distribution-config file:///tmp/cf-off.json --query Distribution.Status --output text
  fi
fi

log "2. 運算層：ASG（強制刪除）、ALB、Launch Template、EC2"
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "${PREFIX}-app-asg" --force-delete
[ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ] && aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
aws ec2 delete-launch-template --launch-template-name "${PREFIX}-app-lt" >/dev/null
if [ -n "$VPC_ID" ]; then
  IDS=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" \
    "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
  [ -n "$IDS" ] && aws ec2 terminate-instances --instance-ids $IDS >/dev/null && echo "終止中：$IDS"
fi

log "3. 資料層：RDS（略過最終快照，RDS 託管的 Secrets Manager 機密會一併刪除）、DynamoDB"
aws rds delete-db-instance --db-instance-identifier "${PREFIX}-lab-mysql" \
  --skip-final-snapshot --delete-automated-backups --query DBInstance.DBInstanceStatus --output text
aws dynamodb delete-table --table-name "${PREFIX}-orders" --query TableDescription.TableStatus --output text

log "4. 無伺服器與整合：Lambda（先記下執行角色）、Log Group、Alarm、SNS 訂閱與主題、SQS"
LAMBDA_ROLE_ARN=$(aws lambda get-function-configuration --function-name "${PREFIX}-order-api" --query Role --output text 2>/dev/null)
aws lambda delete-function --function-name "${PREFIX}-order-api"
aws logs delete-log-group --log-group-name "/aws/lambda/${PREFIX}-order-api"
aws cloudwatch delete-alarms --alarm-names "${PREFIX}-asg-high-cpu"
if [ -n "$TOPIC_ARN" ]; then
  for s in $(aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" --query 'Subscriptions[].SubscriptionArn' --output text); do
    [ "$s" != "PendingConfirmation" ] && aws sns unsubscribe --subscription-arn "$s"
  done
  aws sns delete-topic --topic-arn "$TOPIC_ARN"
fi
[ -n "$Q_URL" ] && [ "$Q_URL" != "None" ] && aws sqs delete-queue --queue-url "$Q_URL"

log "5. Route 53：刪除 A（Alias）記錄，再刪私有託管區域"
if [ -n "$ZONE_ID" ]; then
  aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
    --query "ResourceRecordSets[?Type!='NS' && Type!='SOA']" > /tmp/a.json
  if [ "$(jq length /tmp/a.json)" -gt 0 ]; then
    jq '{Changes:[.[]|{Action:"DELETE",ResourceRecordSet:.}]}' /tmp/a.json > /tmp/del.json
    aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch file:///tmp/del.json >/dev/null
  fi
  aws route53 delete-hosted-zone --id "$ZONE_ID" >/dev/null && echo "託管區域已刪除"
fi

log "6. KMS：刪除別名並排程刪除金鑰（最短 7 天，期間仍可取消）"
if [ -n "$KEY_ID" ] && [ "$KEY_ID" != "None" ]; then
  aws kms delete-alias --alias-name "alias/${PREFIX}-lab-key"
  aws kms schedule-key-deletion --key-id "$KEY_ID" --pending-window-in-days 7 --query KeyState --output text
fi

log "7. S3：刪除所有版本與刪除標記，再刪 Bucket"
for b in $BUCKETS; do
  while :; do
    aws s3api list-object-versions --bucket "$b" --max-items 1000 --output json \
      | jq '{Objects: ([.Versions[]?, .DeleteMarkers[]?] | map({Key, VersionId})), Quiet: true}' > /tmp/objs.json
    [ "$(jq '.Objects|length' /tmp/objs.json)" -gt 0 ] || break
    aws s3api delete-objects --bucket "$b" --delete file:///tmp/objs.json >/dev/null
  done
  aws s3api delete-bucket --bucket "$b" && echo "Bucket 已刪除：$b"
done

log "8. IAM：Lambda 執行角色（含主控台自動建立的 AWSLambdaBasicExecutionRole-* 客戶受管政策）"
R="${LAMBDA_ROLE:-}"
[ -z "$R" ] && [ -n "$LAMBDA_ROLE_ARN" ] && [ "$LAMBDA_ROLE_ARN" != "None" ] && R="${LAMBDA_ROLE_ARN##*/}"
[ -z "$R" ] && R=$(aws iam list-roles --path-prefix /service-role/ \
  --query "Roles[?starts_with(RoleName, '${PREFIX}-order-api-role')].RoleName | [0]" --output text)
if [ -n "$R" ] && [ "$R" != "None" ]; then
  for p in $(aws iam list-role-policies --role-name "$R" --query PolicyNames --output text); do
    aws iam delete-role-policy --role-name "$R" --policy-name "$p"
  done
  for p in $(aws iam list-attached-role-policies --role-name "$R" --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$R" --policy-arn "$p"
    case "$p" in
      arn:aws:iam::aws:*) ;;                                    # AWS 受管政策不能刪
      *:policy/service-role/AWSLambdaBasicExecutionRole-*)     # 主控台自動建立的客戶受管政策
        aws iam delete-policy --policy-arn "$p" && echo "已刪除客戶受管政策 ${p##*/}" ;;
    esac
  done
  aws iam delete-role --role-name "$R" && echo "已刪除角色 $R"
fi

log "9. IAM：EC2 角色與執行個體設定檔"
aws iam remove-role-from-instance-profile --instance-profile-name "${PREFIX}-ec2-ssm-role" --role-name "${PREFIX}-ec2-ssm-role"
aws iam delete-instance-profile --instance-profile-name "${PREFIX}-ec2-ssm-role"
aws iam detach-role-policy --role-name "${PREFIX}-ec2-ssm-role" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role --role-name "${PREFIX}-ec2-ssm-role" && echo "已刪除角色 ${PREFIX}-ec2-ssm-role"

log "10. IAM：Lab 1 的 ${PREFIX}-dev-user（主控台密碼、MFA、政策）與 ${PREFIX}-developers 群組"
U="${PREFIX}-dev-user"
aws iam delete-login-profile --user-name "$U" && echo "已刪除 $U 的主控台密碼（login profile）"
for m in $(aws iam list-mfa-devices --user-name "$U" --query 'MFADevices[].SerialNumber' --output text 2>/dev/null); do
  aws iam deactivate-mfa-device --user-name "$U" --serial-number "$m"
  case "$m" in *:mfa/*) aws iam delete-virtual-mfa-device --serial-number "$m" ;; esac
done
for k in $(aws iam list-access-keys --user-name "$U" --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null); do
  aws iam delete-access-key --user-name "$U" --access-key-id "$k"
done
for p in $(aws iam list-attached-user-policies --user-name "$U" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
  aws iam detach-user-policy --user-name "$U" --policy-arn "$p"        # 例如 IAMUserChangePassword
done
aws iam remove-user-from-group --user-name "$U" --group-name "${PREFIX}-developers"
aws iam delete-user --user-name "$U" && echo "已刪除使用者 $U"
for p in $(aws iam list-attached-group-policies --group-name "${PREFIX}-developers" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
  aws iam detach-group-policy --group-name "${PREFIX}-developers" --policy-arn "$p"
done
aws iam delete-group --group-name "${PREFIX}-developers" && echo "已刪除群組 ${PREFIX}-developers"
# 舊版（v1）腳本建立的 saa-lab-user，若存在一併清除
aws iam remove-user-from-group --user-name "${PREFIX}-lab-user" --group-name "${PREFIX}-developers" 2>/dev/null
aws iam delete-user --user-name "${PREFIX}-lab-user" 2>/dev/null && echo "已刪除舊版使用者 ${PREFIX}-lab-user"
echo "保留：${PREFIX}-admin / ${PREFIX}-admins（Lab 0 的管理員，IAM 不計費）"

log "11. 等待 RDS / EC2 / ALB 刪除完成，再刪 DB 子網路群組與目標群組"
aws rds wait db-instance-deleted --db-instance-identifier "${PREFIX}-lab-mysql"
aws rds delete-db-subnet-group --db-subnet-group-name "${PREFIX}-db-subnets" && echo "DB 子網路群組已刪除"
if [ -n "$VPC_ID" ]; then
  IDS=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" \
    "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
  [ -n "$IDS" ] && aws ec2 terminate-instances --instance-ids $IDS >/dev/null && aws ec2 wait instance-terminated --instance-ids $IDS
fi
[ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ] && aws elbv2 delete-target-group --target-group-arn "$TG_ARN" && echo "目標群組已刪除"

if [ -n "$VPC_ID" ]; then
  log "12. VPC：NAT（全部）→ 釋放彈性 IP → 端點 → SG → 子網路 → 路由表 → IGW → VPC"
  NATS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=pending,available" \
    --query 'NatGateways[].NatGatewayId' --output text)
  EIPS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=pending,available" \
    --query 'NatGateways[].NatGatewayAddresses[].AllocationId' --output text)
  for n in $NATS; do aws ec2 delete-nat-gateway --nat-gateway-id "$n" >/dev/null; done
  [ -n "$NATS" ] && aws ec2 wait nat-gateway-deleted --nat-gateway-ids $NATS && echo "NAT 已刪除：$NATS"
  for e in $EIPS ${EIP_ALLOC:-} ${EIP_ALLOC2:-}; do aws ec2 release-address --allocation-id "$e" 2>/dev/null && echo "已釋放 $e"; done
  for v in $(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query 'VpcEndpoints[].VpcEndpointId' --output text); do
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$v" >/dev/null && echo "端點已刪除：$v"
  done
  sleep 30   # 等 ALB / RDS 的網路介面釋放；SG 刪除失敗時稍後重跑本腳本即可
  for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
              --query "SecurityGroups[?GroupName!='default'].GroupId" --output text); do
    perms=$(aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissions' --output json)
    [ "$perms" != "[]" ] && aws ec2 revoke-security-group-ingress --group-id "$sg" --ip-permissions "$perms" >/dev/null
  done
  for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
              --query "SecurityGroups[?GroupName!='default'].GroupId" --output text); do
    aws ec2 delete-security-group --group-id "$sg" && echo "SG 已刪除：$sg"
  done
  for s in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --subnet-id "$s"
  done
  for r in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" \
             --query 'RouteTables[?!(Associations[?Main])].RouteTableId' --output text); do
    aws ec2 delete-route-table --route-table-id "$r"
  done
  for g in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
             --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws ec2 detach-internet-gateway --internet-gateway-id "$g" --vpc-id "$VPC_ID"
    aws ec2 delete-internet-gateway --internet-gateway-id "$g"
  done
  aws ec2 delete-vpc --vpc-id "$VPC_ID" && echo "VPC 已刪除"
fi

log "13. CloudFront：等停用部署完成後刪除分發，再刪 OAC"
if [ -n "${DIST_ID:-}" ]; then
  echo "等待停用部署完成（約 5–15 分鐘）..."
  aws cloudfront wait distribution-deployed --id "$DIST_ID"
  ETAG=$(aws cloudfront get-distribution --id "$DIST_ID" --query ETag --output text)
  aws cloudfront delete-distribution --id "$DIST_ID" --if-match "$ETAG" && echo "分發已刪除"
fi
if [ -n "$OAC_ID" ]; then
  ETAG=$(aws cloudfront get-origin-access-control --id "$OAC_ID" --query ETag --output text)
  aws cloudfront delete-origin-access-control --id "$OAC_ID" --if-match "$ETAG" && echo "OAC 已刪除"
fi

log "14. 清除後檢查（數字應為 0；CloudFront 無分發時為 0 或 null）"
echo "NAT       $(aws ec2 describe-nat-gateways --filter Name=state,Values=pending,available --query 'length(NatGateways)')"
echo "EIP       $(aws ec2 describe-addresses --query 'length(Addresses)')"
echo "ELB       $(aws elbv2 describe-load-balancers --query 'length(LoadBalancers)')"
echo "RDS       $(aws rds describe-db-instances --query 'length(DBInstances)')"
echo "CF        $(aws cloudfront list-distributions --query 'DistributionList.Quantity')"
echo "SAA_VPC   $(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${N}-vpc" --query 'length(Vpcs)')"
echo "R53_ZONE  $(aws route53 list-hosted-zones-by-name --dns-name saa.internal --query "length(HostedZones[?Name=='saa.internal.'])")"
echo "DEV_USER  $(aws iam get-user --user-name "${PREFIX}-dev-user" >/dev/null 2>&1 && echo 仍存在 || echo 已刪除)"
echo "ADMIN     $(aws iam get-user --user-name "${PREFIX}-admin" >/dev/null 2>&1 && echo "${PREFIX}-admin 保留" || echo "${PREFIX}-admin 不存在")"

log "完成。建議隔天到 Billing → Bills 與 Cost Explorer 再確認一次沒有殘留費用。"
rm -f "$STATE_FILE"

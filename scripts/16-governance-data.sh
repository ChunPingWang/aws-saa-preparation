#!/usr/bin/env bash
# Lab 16：CloudTrail 查詢 ＋ AWS Config（restricted-ssh）＋ Athena 查 S3 ＋ ECS Fargate
source "$(dirname "$0")/00-env.sh"
ROOT="$(dirname "$0")/.."
DEF_VPC=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)

log "CloudTrail：最近 90 天誰建立過 VPC Peering"
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=CreateVpcPeeringConnection \
  --max-results 5 --query 'Events[].[EventTime,Username,EventName]' --output table

log "AWS Config：服務連結角色 + 只記錄 SG + 交付到 S3 + 受管規則 restricted-ssh"
aws iam create-service-linked-role --aws-service-name config.amazonaws.com >/dev/null 2>&1 || true
CB="config-bucket-${ACCOUNT_ID}"
aws s3 mb "s3://$CB" >/dev/null 2>&1 || true
aws s3api put-bucket-policy --bucket "$CB" --policy "{\"Version\":\"2012-10-17\",\"Statement\":[
 {\"Sid\":\"AclCheck\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"config.amazonaws.com\"},\"Action\":\"s3:GetBucketAcl\",\"Resource\":\"arn:aws:s3:::$CB\"},
 {\"Sid\":\"Write\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"config.amazonaws.com\"},\"Action\":\"s3:PutObject\",\"Resource\":\"arn:aws:s3:::$CB/AWSLogs/${ACCOUNT_ID}/Config/*\",
  \"Condition\":{\"StringEquals\":{\"s3:x-amz-acl\":\"bucket-owner-full-control\"}}}]}"
aws configservice put-configuration-recorder --configuration-recorder \
  "name=default,roleARN=arn:aws:iam::${ACCOUNT_ID}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig" \
  --recording-group 'allSupported=false,includeGlobalResourceTypes=false,resourceTypes=AWS::EC2::SecurityGroup'
aws configservice put-delivery-channel --delivery-channel "name=default,s3BucketName=$CB"
aws configservice start-configuration-recorder --configuration-recorder-name default
aws configservice put-config-rule --config-rule \
  '{"ConfigRuleName":"restricted-ssh","Source":{"Owner":"AWS","SourceIdentifier":"INCOMING_SSH_DISABLED"},"Scope":{"ComplianceResourceTypes":["AWS::EC2::SecurityGroup"]}}'

log "故意建立不合規的 SG：22/0.0.0.0/0（不掛到任何執行個體）"
BAD=$(aws ec2 create-security-group --group-name "${PREFIX}-bad-ssh-sg" --vpc-id "$DEF_VPC" \
  --description "Config demo: SSH open to the world (do not attach)" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$BAD" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null
save_state BAD_SG "$BAD"

log "Athena：上傳 orders.csv → 設定 primary 結果位置 → 建資料庫 / 資料表 → 查詢"
AB="${PREFIX}-lab-athena-${ACCOUNT_ID}"
aws s3 mb "s3://$AB" >/dev/null
aws s3 cp "$ROOT/test-data/site/orders.csv" "s3://$AB/orders/orders.csv" >/dev/null
aws athena update-work-group --work-group primary \
  --configuration-updates "ResultConfigurationUpdates={OutputLocation=s3://$AB/results/}"
run_q() {   # run_q 'SQL' → 等待完成並印出結果
  local id st
  id=$(aws athena start-query-execution --work-group primary --query-string "$1" --query QueryExecutionId --output text)
  while :; do
    st=$(aws athena get-query-execution --query-execution-id "$id" --query QueryExecution.Status.State --output text)
    case "$st" in SUCCEEDED|FAILED|CANCELLED) break ;; esac; sleep 2
  done
  echo "[$st] $(aws athena get-query-execution --query-execution-id "$id" --query 'QueryExecution.Statistics.DataScannedInBytes' --output text) bytes scanned"
  [ "$st" = SUCCEEDED ] && aws athena get-query-results --query-execution-id "$id" \
    --query 'ResultSet.Rows[].Data[].VarCharValue' --output text | head -20
}
sed "s/<ACCOUNT_ID>/${ACCOUNT_ID}/" "$ROOT/athena/orders.sql" | grep -v '^--' | tr '\n' ' ' | tr ';' '\n' \
  | sed 's/^ *//' | grep -v '^$' | while read -r stmt; do run_q "$stmt"; done

log "ECS Fargate：叢集 → 任務定義 → 執行任務（公有子網路 + 公有 IP）"
aws iam create-role --role-name ecsTaskExecutionRole --assume-role-policy-document \
 '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null 2>&1 \
 && aws iam attach-role-policy --role-name ecsTaskExecutionRole \
      --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws ecs create-cluster --cluster-name "${PREFIX}-ecs-cluster" --capacity-providers FARGATE FARGATE_SPOT \
  --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 >/dev/null
ESG=$(aws ec2 create-security-group --group-name "${PREFIX}-ecs-sg" --vpc-id "$DEF_VPC" \
  --description "SAA lab ECS task: HTTP 80" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$ESG" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
sleep 10
aws ecs register-task-definition --family "${PREFIX}-nginx" --requires-compatibilities FARGATE \
  --network-mode awsvpc --cpu 256 --memory 512 \
  --execution-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/ecsTaskExecutionRole" \
  --runtime-platform cpuArchitecture=X86_64,operatingSystemFamily=LINUX \
  --container-definitions '[{"name":"web","image":"public.ecr.aws/nginx/nginx:stable-alpine","essential":true,"portMappings":[{"containerPort":80,"protocol":"tcp"}]}]' >/dev/null
SUBS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$DEF_VPC" Name=default-for-az,Values=true \
  --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
TASK=$(aws ecs run-task --cluster "${PREFIX}-ecs-cluster" --task-definition "${PREFIX}-nginx" --count 1 \
  --capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBS],securityGroups=[$ESG],assignPublicIp=ENABLED}" \
  --query 'tasks[0].taskArn' --output text)
aws ecs wait tasks-running --cluster "${PREFIX}-ecs-cluster" --tasks "$TASK"
ENI=$(aws ecs describe-tasks --cluster "${PREFIX}-ecs-cluster" --tasks "$TASK" \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text)
PIP=$(aws ec2 describe-network-interfaces --network-interface-ids "$ENI" --query 'NetworkInterfaces[0].Association.PublicIp' --output text)
sleep 10; curl -s "http://$PIP/" | grep -o '<title>.*</title>'

log "Config 評估結果（建立後數分鐘才會出現）"
sleep 60
aws configservice get-compliance-details-by-config-rule --config-rule-name restricted-ssh \
  --query 'EvaluationResults[].[EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId,ComplianceType]' --output table

#!/usr/bin/env bash
# =============================================================
# 清除 Lab 13–16 的資源（依名稱 / 標籤查找，主控台或腳本建立的都適用；可重複執行）
# 99-cleanup.sh 會在最後呼叫本腳本；也可以單獨執行：./scripts/98-cleanup-labs13-16.sh
# 會永久刪除 EBS / EFS / S3 資料，執行前請確認。執行身分：saa-admin
# =============================================================
source "$(dirname "$0")/00-env.sh"
set +e +u
P="${PREFIX}"
q() { "$@" 2>/dev/null; }
if [ -z "${SAA_CLEANUP_CONFIRMED:-}" ]; then
  read -r -p "確定要刪除 Lab 13–16 的資源？輸入 yes 繼續：" ans
  [ "$ans" = "yes" ] || { echo "已取消"; exit 0; }
fi
DEF_VPC=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
PV=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${P}-peer-vpc" --query 'Vpcs[0].VpcId' --output text)
[ "$PV" = "None" ] && PV=""

log "Lab 16-1 ECS：停止任務 → 刪叢集 → 取消註冊並刪除任務定義 → Log Group"
for t in $(q aws ecs list-tasks --cluster "${P}-ecs-cluster" --query 'taskArns' --output text); do
  aws ecs stop-task --cluster "${P}-ecs-cluster" --task "$t" --query 'task.lastStatus' --output text
done
for td in $(q aws ecs list-task-definitions --family-prefix "${P}-nginx" --query 'taskDefinitionArns' --output text); do
  aws ecs deregister-task-definition --task-definition "$td" >/dev/null
  q aws ecs delete-task-definitions --task-definitions "$td" >/dev/null
done
sleep 20
q aws ecs delete-cluster --cluster "${P}-ecs-cluster" --query 'cluster.status' --output text
q aws logs delete-log-group --log-group-name "/ecs/${P}-nginx"

log "Lab 16-2 Config：停止記錄 → 刪規則 → 刪交付管道與記錄器 → 清空並刪除 config-bucket"
REC=$(q aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[0].name' --output text)
if [ -n "$REC" ] && [ "$REC" != "None" ]; then
  aws configservice stop-configuration-recorder --configuration-recorder-name "$REC"
  q aws configservice delete-config-rule --config-rule-name restricted-ssh
  CH=$(aws configservice describe-delivery-channels --query 'DeliveryChannels[0].name' --output text)
  [ "$CH" != "None" ] && aws configservice delete-delivery-channel --delivery-channel-name "$CH"
  aws configservice delete-configuration-recorder --configuration-recorder-name "$REC" && echo "Config 記錄器已刪除"
fi
for b in $(aws s3api list-buckets --query "Buckets[?starts_with(Name,'config-bucket-${ACCOUNT_ID}')].Name" --output text); do
  aws s3 rb "s3://$b" --force >/dev/null && echo "已刪除 $b"
done

log "Lab 16-3 Athena / Glue：刪資料表與資料庫 → 還原 primary 工作群組結果位置 → 刪 Bucket"
q aws glue delete-table --database-name saa_lab --name orders
q aws glue delete-database --name saa_lab && echo "Glue 資料庫 saa_lab 已刪除"
q aws athena update-work-group --work-group primary \
  --configuration-updates 'ResultConfigurationUpdates={RemoveOutputLocation=true}'
q aws s3 rb "s3://${P}-lab-athena-${ACCOUNT_ID}" --force >/dev/null && echo "已刪除 ${P}-lab-athena-${ACCOUNT_ID}"

log "Lab 15：EventBridge 規則 → Step Functions → API Gateway → Lambda"
for t in $(q aws events list-targets-by-rule --rule "${P}-order-created-rule" --query 'Targets[].Id' --output text); do
  aws events remove-targets --rule "${P}-order-created-rule" --ids "$t" >/dev/null
done
q aws events delete-rule --name "${P}-order-created-rule" && echo "EventBridge 規則已刪除"
SM=$(aws stepfunctions list-state-machines --query "stateMachines[?name=='${P}-order-flow'].stateMachineArn | [0]" --output text)
[ "$SM" != "None" ] && aws stepfunctions delete-state-machine --state-machine-arn "$SM" && echo "狀態機已刪除"
for id in $(aws apigateway get-rest-apis --query "items[?name=='${P}-hello-api'].id" --output text); do
  aws apigateway delete-rest-api --rest-api-id "$id" && echo "REST API $id 已刪除"
done
HELLO_ROLE=$(q aws lambda get-function-configuration --function-name "${P}-hello" --query Role --output text)
q aws lambda delete-function --function-name "${P}-hello" && echo "Lambda ${P}-hello 已刪除"
q aws logs delete-log-group --log-group-name "/aws/lambda/${P}-hello"

log "Lab 15/16：主控台自動建立的 IAM 角色（先刪內嵌政策、卸離並刪除客戶受管政策）"
del_role() {   # del_role ROLE_NAME
  local r="$1" p
  [ -z "$r" ] || [ "$r" = "None" ] && return
  for p in $(q aws iam list-role-policies --role-name "$r" --query PolicyNames --output text); do
    aws iam delete-role-policy --role-name "$r" --policy-name "$p"
  done
  for p in $(q aws iam list-attached-role-policies --role-name "$r" --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$r" --policy-arn "$p"
    case "$p" in arn:aws:iam::aws:*) ;; *) q aws iam delete-policy --policy-arn "$p" ;; esac
  done
  q aws iam delete-role --role-name "$r" && echo "已刪除角色 $r"
}
del_role "${HELLO_ROLE##*/}"
for r in $(aws iam list-roles --query "Roles[?starts_with(RoleName,'StepFunctions-${P}-order-flow-role') || starts_with(RoleName,'Amazon_EventBridge_Invoke_Step_Functions') || RoleName=='${P}-flowlogs-role' || RoleName=='${P}-order-flow-role' || RoleName=='${P}-eventbridge-sfn-role'].RoleName" --output text); do
  del_role "$r"
done

log "Lab 14：Flow Logs → NACL → Peering 與路由 → peer 執行個體 → peer VPC"
for f in $(aws ec2 describe-flow-logs --filter "Name=log-group-name,Values=/${P}/vpc-flow-logs" --query 'FlowLogs[].FlowLogId' --output text); do
  aws ec2 delete-flow-logs --flow-log-ids "$f" >/dev/null && echo "Flow Log $f 已刪除"
done
q aws logs delete-log-group --log-group-name "/${P}/vpc-flow-logs"
for pcx in $(aws ec2 describe-vpc-peering-connections --filters "Name=tag:Name,Values=${P}-default-to-peer" \
             "Name=status-code,Values=active,pending-acceptance" --query 'VpcPeeringConnections[].VpcPeeringConnectionId' --output text); do
  for rt in $(aws ec2 describe-route-tables --filters "Name=route.vpc-peering-connection-id,Values=$pcx" --query 'RouteTables[].RouteTableId' --output text); do
    for c in $(aws ec2 describe-route-tables --route-table-ids "$rt" \
               --query "RouteTables[0].Routes[?VpcPeeringConnectionId=='$pcx'].DestinationCidrBlock" --output text); do
      aws ec2 delete-route --route-table-id "$rt" --destination-cidr-block "$c" && echo "已刪除路由 $rt $c"
    done
  done
  aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id "$pcx" >/dev/null && echo "Peering $pcx 已刪除"
done

log "Lab 13/14：終止執行個體"
IDS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${P}-storage-a,${P}-storage-b,${P}-peer-b" \
  "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text)
[ -n "$IDS" ] && aws ec2 terminate-instances --instance-ids $IDS >/dev/null && echo "終止中：$IDS"

log "Lab 13：EFS（先刪掛載目標）"
for fs in $(aws efs describe-file-systems --query "FileSystems[?Name=='${P}-efs'].FileSystemId" --output text); do
  for mt in $(aws efs describe-mount-targets --file-system-id "$fs" --query 'MountTargets[].MountTargetId' --output text); do
    aws efs delete-mount-target --mount-target-id "$mt"
  done
  until [ "$(aws efs describe-mount-targets --file-system-id "$fs" --query 'length(MountTargets)')" = 0 ]; do sleep 10; done
  aws efs delete-file-system --file-system-id "$fs" && echo "EFS $fs 已刪除"
done

[ -n "$IDS" ] && aws ec2 wait instance-terminated --instance-ids $IDS && echo "執行個體已終止"

log "Lab 13：AMI（取消註冊 + 刪除其快照）→ 資料快照 → 資料磁碟區"
for img in $(aws ec2 describe-images --owners self --filters "Name=name,Values=${P}-storage-ami" --query 'Images[].ImageId' --output text); do
  SNAPS=$(aws ec2 describe-images --image-ids "$img" --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' --output text)
  aws ec2 deregister-image --image-id "$img" && echo "AMI $img 已取消註冊"
  for s in $SNAPS; do aws ec2 delete-snapshot --snapshot-id "$s" && echo "快照 $s 已刪除"; done
done
for s in $(aws ec2 describe-snapshots --owner-ids self --filters "Name=tag:Name,Values=${P}-data-snap" --query 'Snapshots[].SnapshotId' --output text); do
  aws ec2 delete-snapshot --snapshot-id "$s" && echo "快照 $s 已刪除"
done
for v in $(aws ec2 describe-volumes --filters "Name=tag:Name,Values=${P}-data-vol,${P}-data-vol-b" --query 'Volumes[].VolumeId' --output text); do
  aws ec2 delete-volume --volume-id "$v" && echo "磁碟區 $v 已刪除"
done

log "Lab 14：peer VPC（NACL → SG → 子網路 → 路由表 → IGW → VPC）"
if [ -n "$PV" ]; then
  sleep 20
  for a in $(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$PV" "Name=default,Values=false" --query 'NetworkAcls[].NetworkAclId' --output text); do
    DEF_ACL=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$PV" "Name=default,Values=true" --query 'NetworkAcls[0].NetworkAclId' --output text)
    for as in $(aws ec2 describe-network-acls --network-acl-ids "$a" --query 'NetworkAcls[0].Associations[].NetworkAclAssociationId' --output text); do
      aws ec2 replace-network-acl-association --association-id "$as" --network-acl-id "$DEF_ACL" >/dev/null
    done
    aws ec2 delete-network-acl --network-acl-id "$a" && echo "NACL $a 已刪除"
  done
  for sg in $(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$PV" --query "SecurityGroups[?GroupName!='default'].GroupId" --output text); do
    aws ec2 delete-security-group --group-id "$sg" && echo "SG $sg 已刪除"
  done
  for s in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$PV" --query 'Subnets[].SubnetId' --output text); do aws ec2 delete-subnet --subnet-id "$s"; done
  for rt in $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$PV" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text); do
    aws ec2 delete-route-table --route-table-id "$rt"
  done
  for igw in $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$PV" --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$PV" && aws ec2 delete-internet-gateway --internet-gateway-id "$igw"
  done
  aws ec2 delete-vpc --vpc-id "$PV" && echo "VPC $PV 已刪除"
fi

log "預設 VPC 中的 Lab SG（saa-storage-sg、saa-ecs-sg、saa-bad-ssh-sg）"
sleep 10
for n in "${P}-storage-sg" "${P}-ecs-sg" "${P}-bad-ssh-sg"; do
  sg=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$DEF_VPC" "Name=group-name,Values=$n" --query 'SecurityGroups[0].GroupId' --output text)
  [ "$sg" = "None" ] && continue
  perms=$(aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0].IpPermissions' --output json)
  [ "$perms" != "[]" ] && aws ec2 revoke-security-group-ingress --group-id "$sg" --ip-permissions "$perms" >/dev/null
  aws ec2 delete-security-group --group-id "$sg" && echo "SG $n ($sg) 已刪除"
done
# ecsTaskExecutionRole 是 ECS 主控台共用的預設角色，帳號裡其他服務可能也在用，這裡刻意不刪。
# 確定只有本 Lab 使用時再手動刪除：aws iam detach-role-policy --role-name ecsTaskExecutionRole \
#   --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy && aws iam delete-role --role-name ecsTaskExecutionRole
echo "Lab 13–16 清除完成（saa-ec2-ssm-role 由 99-cleanup.sh 處理；ecsTaskExecutionRole 請自行判斷是否刪除）"

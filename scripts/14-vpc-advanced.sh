#!/usr/bin/env bash
# Lab 14：VPC Peering + VPC Flow Logs + NACL（無狀態、依規則編號由小到大比對）
# 前置：Lab 13 的 ${PREFIX}-storage-a（預設 VPC 172.31.0.0/16，us-east-1a）
source "$(dirname "$0")/00-env.sh"
INST_A="${INST_A:-$(aws ec2 describe-instances --filters Name=tag:Name,Values=${PREFIX}-storage-a Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text)}"
DEF_VPC="${DEF_VPC:-$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)}"
DEF_CIDR=$(aws ec2 describe-vpcs --vpc-ids "$DEF_VPC" --query 'Vpcs[0].CidrBlock' --output text)

log "建立 ${PREFIX}-peer-vpc 10.20.0.0/16 + 公有子網路 10.20.0.0/20（us-east-1a）+ IGW"
PV=$(aws ec2 create-vpc --cidr-block 10.20.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PREFIX}-peer-vpc}]" --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id "$PV" --enable-dns-hostnames
PSUB=$(aws ec2 create-subnet --vpc-id "$PV" --cidr-block 10.20.0.0/20 --availability-zone us-east-1a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PREFIX}-peer-subnet-public1-us-east-1a}]" --query Subnet.SubnetId --output text)
IGW=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$PV"
PRT=$(aws ec2 create-route-table --vpc-id "$PV" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PREFIX}-peer-rtb-public}]" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$PRT" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" >/dev/null
aws ec2 associate-route-table --route-table-id "$PRT" --subnet-id "$PSUB" >/dev/null
save_state PEER_VPC "$PV"; save_state PEER_SUB "$PSUB"; save_state PEER_IGW "$IGW"; save_state PEER_RTB "$PRT"

log "SG ${PREFIX}-peer-sg：允許來自預設 VPC 的 ICMP"
PSG=$(aws ec2 create-security-group --group-name "${PREFIX}-peer-sg" --vpc-id "$PV" \
  --description "ICMP from default VPC via peering" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$PSG" \
  --ip-permissions "IpProtocol=icmp,FromPort=-1,ToPort=-1,IpRanges=[{CidrIp=$DEF_CIDR}]" >/dev/null
save_state PEER_SG "$PSG"

AMI_ID=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
PEER_INST=$(aws ec2 run-instances --image-id "$AMI_ID" --instance-type t3.micro --subnet-id "$PSUB" \
  --security-group-ids "$PSG" --associate-public-ip-address --iam-instance-profile Name="${PREFIX}-ec2-ssm-role" \
  --metadata-options HttpTokens=required \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PREFIX}-peer-b}]" \
  --query 'Instances[0].InstanceId' --output text)
save_state PEER_INST "$PEER_INST"
aws ec2 wait instance-running --instance-ids "$PEER_INST"
PEER_IP=$(aws ec2 describe-instances --instance-ids "$PEER_INST" --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

log "VPC Peering：預設 VPC（請求者）↔ ${PREFIX}-peer-vpc（接受者），同帳號同區域仍需「接受」"
PCX=$(aws ec2 create-vpc-peering-connection --vpc-id "$DEF_VPC" --peer-vpc-id "$PV" \
  --tag-specifications "ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=${PREFIX}-default-to-peer}]" \
  --query VpcPeeringConnection.VpcPeeringConnectionId --output text)
aws ec2 wait vpc-peering-connection-exists --vpc-peering-connection-ids "$PCX"
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id "$PCX" >/dev/null
save_state PCX "$PCX"

log "兩邊路由表都要加路由（Peering 不可遞移，也不會自動加路由）"
DEF_RT=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values="$DEF_VPC" Name=association.main,Values=true --query 'RouteTables[0].RouteTableId' --output text)
aws ec2 create-route --route-table-id "$DEF_RT" --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id "$PCX" >/dev/null
aws ec2 create-route --route-table-id "$PRT" --destination-cidr-block "$DEF_CIDR" --vpc-peering-connection-id "$PCX" >/dev/null
save_state DEF_RT "$DEF_RT"

log "Flow Logs：${PREFIX}-peer-vpc → CloudWatch Logs /${PREFIX}/vpc-flow-logs（彙總間隔 1 分鐘）"
ROLE=${PREFIX}-flowlogs-role
aws iam create-role --role-name "$ROLE" --assume-role-policy-document \
 '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"vpc-flow-logs.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
aws iam put-role-policy --role-name "$ROLE" --policy-name flowlogs-to-cwl --policy-document \
 '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents","logs:DescribeLogGroups","logs:DescribeLogStreams"],"Resource":"*"}]}'
sleep 10
aws logs create-log-group --log-group-name "/${PREFIX}/vpc-flow-logs"
aws logs put-retention-policy --log-group-name "/${PREFIX}/vpc-flow-logs" --retention-in-days 1
aws ec2 create-flow-logs --resource-type VPC --resource-ids "$PV" --traffic-type ALL \
  --log-destination-type cloud-watch-logs --log-group-name "/${PREFIX}/vpc-flow-logs" \
  --deliver-logs-permission-arn "arn:aws:iam::${ACCOUNT_ID}:role/$ROLE" --max-aggregation-interval 60 \
  --tag-specifications "ResourceType=vpc-flow-log,Tags=[{Key=Name,Value=${PREFIX}-peer-flowlog}]" >/dev/null

ping_from_a() {
  local cid
  cid=$(aws ssm send-command --instance-ids "$INST_A" --document-name AWS-RunShellScript \
    --parameters "$(jq -cn --arg c "ping -c 3 -W 2 $PEER_IP || true" '{commands:[$c]}')" --query Command.CommandId --output text)
  sleep 12; aws ssm get-command-invocation --command-id "$cid" --instance-id "$INST_A" --query StandardOutputContent --output text
}
log "從 ${PREFIX}-storage-a ping ${PREFIX}-peer-b（$PEER_IP）→ 應成功"
sleep 30; ping_from_a

log "NACL ${PREFIX}-peer-nacl：規則 90 DENY 來自 $DEF_CIDR 的 ICMP，100 ALLOW ALL（進出都要設，因為無狀態）"
NACL=$(aws ec2 create-network-acl --vpc-id "$PV" \
  --tag-specifications "ResourceType=network-acl,Tags=[{Key=Name,Value=${PREFIX}-peer-nacl}]" --query NetworkAcl.NetworkAclId --output text)
aws ec2 create-network-acl-entry --network-acl-id "$NACL" --ingress --rule-number 90 --protocol 1 --icmp-type-code Code=-1,Type=-1 --cidr-block "$DEF_CIDR" --rule-action deny
aws ec2 create-network-acl-entry --network-acl-id "$NACL" --ingress --rule-number 100 --protocol -1 --cidr-block 0.0.0.0/0 --rule-action allow
aws ec2 create-network-acl-entry --network-acl-id "$NACL" --egress  --rule-number 100 --protocol -1 --cidr-block 0.0.0.0/0 --rule-action allow
OLD_ASSOC=$(aws ec2 describe-network-acls --filters Name=association.subnet-id,Values="$PSUB" \
  --query "NetworkAcls[0].Associations[?SubnetId=='$PSUB'].NetworkAclAssociationId | [0]" --output text)
aws ec2 replace-network-acl-association --association-id "$OLD_ASSOC" --network-acl-id "$NACL" >/dev/null
save_state PEER_NACL "$NACL"
log "再 ping 一次 → 應失敗（SG 允許，但 NACL 先擋）"
sleep 15; ping_from_a

log "Flow Logs 查 REJECT（約 1–5 分鐘後才會出現）"
sleep 90
aws logs filter-log-events --log-group-name "/${PREFIX}/vpc-flow-logs" --filter-pattern '"REJECT"' \
  --max-items 5 --query 'events[].message' --output text

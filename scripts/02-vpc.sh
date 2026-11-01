#!/usr/bin/env bash
# =============================================================
# Lab 2：自建 VPC，與主控台「VPC 和更多」（名稱標籤 saa-lab）建立的結果一致：
#   - VPC 10.0.0.0/16，啟用 DNS 主機名稱與 DNS 解析
#   - 4 個 /20 子網路：public1 10.0.0.0/20、public2 10.0.16.0/20、
#                      private1 10.0.128.0/20、private2 10.0.144.0/20
#   - IGW、公有路由表 saa-lab-rtb-public（兩個公有子網路共用）
#   - Zonal NAT 閘道（預設 1 個，放在 public1）
#   - 私有路由表「每個 AZ 一張」：saa-lab-rtb-private1-us-east-1a / private2-us-east-1b
#   - S3 閘道端點 saa-lab-vpce-s3，關聯到兩張私有路由表
# 注意：精靈建立的公有子網路「自動指派公有 IPv4」= 否，本腳本也維持預設，
#       Lab 3 啟動 EC2 時再指定公有 IP。
#
# 高可用選項：NAT_PER_AZ=1 ./scripts/02-vpc.sh → 每個 AZ 各一個 NAT（費用加倍）
# =============================================================
source "$(dirname "$0")/00-env.sh"
AZ1="${AWS_REGION}a"; AZ2="${AWS_REGION}b"
NAME="${PREFIX}-lab"
NAT_PER_AZ="${NAT_PER_AZ:-0}"

tag() { echo "ResourceType=$1,Tags=[{Key=Name,Value=$2}]"; }

log "建立 VPC 10.0.0.0/16 並啟用 DNS"
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --tag-specifications "$(tag vpc "${NAME}-vpc")" --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
save_state VPC_ID "$VPC_ID"

mk_subnet() { # name cidr az
  aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$2" --availability-zone "$3" \
    --tag-specifications "$(tag subnet "$1")" --query Subnet.SubnetId --output text
}
log "建立 4 個 /20 子網路（每個 4,096 個位址，AWS 保留 5 個 → 4,091 可用）"
PUB1=$(mk_subnet "${NAME}-subnet-public1-$AZ1"  10.0.0.0/20   "$AZ1")
PUB2=$(mk_subnet "${NAME}-subnet-public2-$AZ2"  10.0.16.0/20  "$AZ2")
PRI1=$(mk_subnet "${NAME}-subnet-private1-$AZ1" 10.0.128.0/20 "$AZ1")
PRI2=$(mk_subnet "${NAME}-subnet-private2-$AZ2" 10.0.144.0/20 "$AZ2")
save_state PUB1 "$PUB1"; save_state PUB2 "$PUB2"; save_state PRI1 "$PRI1"; save_state PRI2 "$PRI2"

log "建立並附加 Internet Gateway ${NAME}-igw"
IGW_ID=$(aws ec2 create-internet-gateway --tag-specifications "$(tag internet-gateway "${NAME}-igw")" \
  --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
save_state IGW_ID "$IGW_ID"

log "公有路由表 ${NAME}-rtb-public：0.0.0.0/0 → IGW（兩個公有子網路共用）"
RTB_PUB=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
  --tag-specifications "$(tag route-table "${NAME}-rtb-public")" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$RTB_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_PUB" --subnet-id "$PUB1" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_PUB" --subnet-id "$PUB2" >/dev/null
save_state RTB_PUB "$RTB_PUB"

mk_nat() { # subnet name → 輸出 "EIP_ALLOC NAT_ID"
  local eip nat
  eip=$(aws ec2 allocate-address --domain vpc --tag-specifications "$(tag elastic-ip "$2-eip")" \
    --query AllocationId --output text)
  nat=$(aws ec2 create-nat-gateway --subnet-id "$1" --allocation-id "$eip" \
    --tag-specifications "$(tag natgateway "$2")" --query NatGateway.NatGatewayId --output text)
  echo "$eip $nat"
}
log "Zonal NAT 閘道（放在公有子網路，需要彈性 IP）— 每小時計費，練習完請立即清理"
read -r EIP_ALLOC NAT_ID < <(mk_nat "$PUB1" "${NAME}-nat-public1-$AZ1")
save_state EIP_ALLOC "$EIP_ALLOC"; save_state NAT_ID "$NAT_ID"
NAT_FOR_AZ2="$NAT_ID"
if [ "$NAT_PER_AZ" = "1" ]; then
  log "NAT_PER_AZ=1：在 public2 再建一個 NAT，讓 us-east-1b 的私有子網路不依賴 us-east-1a"
  read -r EIP_ALLOC2 NAT_ID2 < <(mk_nat "$PUB2" "${NAME}-nat-public2-$AZ2")
  save_state EIP_ALLOC2 "$EIP_ALLOC2"; save_state NAT_ID2 "$NAT_ID2"
  NAT_FOR_AZ2="$NAT_ID2"
fi
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_ID ${NAT_ID2:-}

log "私有路由表：每個 AZ 一張，0.0.0.0/0 → NAT"
mk_private_rtb() { # name subnet nat
  local rtb
  rtb=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
    --tag-specifications "$(tag route-table "$1")" --query RouteTable.RouteTableId --output text)
  aws ec2 create-route --route-table-id "$rtb" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$3" >/dev/null
  aws ec2 associate-route-table --route-table-id "$rtb" --subnet-id "$2" >/dev/null
  echo "$rtb"
}
RTB_PRI1=$(mk_private_rtb "${NAME}-rtb-private1-$AZ1" "$PRI1" "$NAT_ID")
RTB_PRI2=$(mk_private_rtb "${NAME}-rtb-private2-$AZ2" "$PRI2" "$NAT_FOR_AZ2")
save_state RTB_PRI1 "$RTB_PRI1"; save_state RTB_PRI2 "$RTB_PRI2"

log "S3 閘道端點 ${NAME}-vpce-s3（免費；在兩張私有路由表加入 S3 前綴清單路由）"
VPCE_ID=$(aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --vpc-endpoint-type Gateway \
  --service-name "com.amazonaws.${AWS_REGION}.s3" --route-table-ids "$RTB_PRI1" "$RTB_PRI2" \
  --tag-specifications "$(tag vpc-endpoint "${NAME}-vpce-s3")" \
  --query VpcEndpoint.VpcEndpointId --output text)
save_state VPCE_ID "$VPCE_ID"

log "驗證子網路（可用 IP 數：/20 = 4,096 − 5 = 4,091；放了 NAT 的子網路會再少 1）"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,SubnetId,AvailabilityZone,AvailabilityZoneId,CidrBlock,AvailableIpAddressCount,MapPublicIpOnLaunch]' \
  --output table
log "驗證路由表"
for r in "$RTB_PUB" "$RTB_PRI1" "$RTB_PRI2"; do
  aws ec2 describe-route-tables --route-table-ids "$r" \
    --query 'RouteTables[0].Routes[].[DestinationCidrBlock||DestinationPrefixListId,GatewayId||NatGatewayId,State]' \
    --output text | sed "s/^/$r  /"
done

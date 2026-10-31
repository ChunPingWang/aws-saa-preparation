#!/usr/bin/env bash
# Lab 2：自建 VPC（2 AZ × 公有/私有子網路、IGW、1 個 NAT Gateway、S3 Gateway Endpoint）
source "$(dirname "$0")/00-env.sh"
AZ1="${AWS_REGION}a"; AZ2="${AWS_REGION}b"

log "建立 VPC 10.0.0.0/16 並啟用 DNS"
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PREFIX}-lab-vpc}]" \
  --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
save_state VPC_ID "$VPC_ID"

mk_subnet() { # name cidr az
  aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$2" --availability-zone "$3" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$1}]" \
    --query Subnet.SubnetId --output text
}
log "建立 4 個子網路（與主控台『VPC 及更多』預設 CIDR 相同）"
PUB1=$(mk_subnet "${PREFIX}-lab-subnet-public1-$AZ1"  10.0.0.0/20   "$AZ1")
PUB2=$(mk_subnet "${PREFIX}-lab-subnet-public2-$AZ2"  10.0.16.0/20  "$AZ2")
PRI1=$(mk_subnet "${PREFIX}-lab-subnet-private1-$AZ1" 10.0.128.0/20 "$AZ1")
PRI2=$(mk_subnet "${PREFIX}-lab-subnet-private2-$AZ2" 10.0.144.0/20 "$AZ2")
for s in "$PUB1" "$PUB2"; do
  aws ec2 modify-subnet-attribute --subnet-id "$s" --map-public-ip-on-launch
done
save_state PUB1 "$PUB1"; save_state PUB2 "$PUB2"; save_state PRI1 "$PRI1"; save_state PRI2 "$PRI2"

log "建立並附加 Internet Gateway"
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PREFIX}-lab-igw}]" \
  --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
save_state IGW_ID "$IGW_ID"

log "公有路由表：0.0.0.0/0 → IGW"
RTB_PUB=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PREFIX}-lab-rtb-public}]" \
  --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$RTB_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_PUB" --subnet-id "$PUB1" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_PUB" --subnet-id "$PUB2" >/dev/null
save_state RTB_PUB "$RTB_PUB"

log "NAT Gateway（放在 public1，含 Elastic IP）— 每小時計費，練習完請立即清理"
EIP_ALLOC=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
NAT_ID=$(aws ec2 create-nat-gateway --subnet-id "$PUB1" --allocation-id "$EIP_ALLOC" \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${PREFIX}-lab-nat}]" \
  --query NatGateway.NatGatewayId --output text)
save_state EIP_ALLOC "$EIP_ALLOC"; save_state NAT_ID "$NAT_ID"
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID"

log "私有路由表：0.0.0.0/0 → NAT（兩個私有子網路共用同一個 NAT，為省錢；正式環境請每 AZ 一個）"
RTB_PRI=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PREFIX}-lab-rtb-private}]" \
  --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$RTB_PRI" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_PRI" --subnet-id "$PRI1" >/dev/null
aws ec2 associate-route-table --route-table-id "$RTB_PRI" --subnet-id "$PRI2" >/dev/null
save_state RTB_PRI "$RTB_PRI"

log "S3 Gateway Endpoint（免費，讓私有子網路存取 S3 不經 NAT）"
VPCE_ID=$(aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --vpc-endpoint-type Gateway \
  --service-name "com.amazonaws.${AWS_REGION}.s3" --route-table-ids "$RTB_PRI" \
  --query VpcEndpoint.VpcEndpointId --output text)
save_state VPCE_ID "$VPCE_ID"

log "驗證子網路"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,SubnetId,AvailabilityZone,CidrBlock]' --output table

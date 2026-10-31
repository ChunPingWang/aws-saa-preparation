#!/usr/bin/env bash
# Lab 3：Security Group + EC2（公有子網路、IAM 角色、User Data、IMDSv2）+ SSM 連線
source "$(dirname "$0")/00-env.sh"
ROOT="$(dirname "$0")/.."

log "建立 ${PREFIX}-web-sg：HTTP 80 對 0.0.0.0/0 開放（不開 22）"
WEB_SG=$(aws ec2 create-security-group --group-name "${PREFIX}-web-sg" \
  --description "Allow HTTP from anywhere for SAA lab web server" --vpc-id "$VPC_ID" \
  --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$WEB_SG" --ip-permissions \
  'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description="HTTP from anywhere"}]' >/dev/null
save_state WEB_SG "$WEB_SG"

log "取得最新 Amazon Linux 2023 AMI（SSM 公開參數）"
AMI_ID=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)
save_state AMI_ID "$AMI_ID"

log "啟動 ${PREFIX}-web-01（t3.micro、public1、無金鑰對、IMDSv2 required）"
WEB_ID=$(aws ec2 run-instances --image-id "$AMI_ID" --instance-type t3.micro \
  --subnet-id "$PUB1" --security-group-ids "$WEB_SG" --associate-public-ip-address \
  --iam-instance-profile Name="${PREFIX}-ec2-ssm-role" \
  --metadata-options HttpTokens=required \
  --user-data "file://$ROOT/userdata/web-userdata.sh" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PREFIX}-web-01}]" \
  --query 'Instances[0].InstanceId' --output text)
save_state WEB_ID "$WEB_ID"
aws ec2 wait instance-status-ok --instance-ids "$WEB_ID"

PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$WEB_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
log "測試 HTTP：http://$PUBLIC_IP/"
sleep 30; curl -s "http://$PUBLIC_IP/"; echo

log "確認 SSM Agent 已註冊（可用 Session Manager 連線，不需 SSH / 22 port）"
aws ssm describe-instance-information --query 'InstanceInformationList[].[InstanceId,PingStatus,PlatformName]' --output table
echo "連線指令：aws ssm start-session --target $WEB_ID"

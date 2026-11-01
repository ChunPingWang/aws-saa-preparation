#!/usr/bin/env bash
# Lab 4：SG 串接（ALB SG → App SG）、Launch Template、Target Group、ALB、Auto Scaling Group
# 與主控台流程相同：先建目標群組 → 獨立建立 ALB（掛 saa-alb-sg、轉送到 saa-app-tg）
#                   → 啟動範本 → ASG「連接到現有的負載平衡器（目標群組）」
source "$(dirname "$0")/00-env.sh"
ROOT="$(dirname "$0")/.."

log "ALB SG（80 from anywhere）與 App SG（80 只允許來自 ALB SG）"
ALB_SG=$(aws ec2 create-security-group --group-name "${PREFIX}-alb-sg" --description "ALB HTTP from anywhere" \
  --vpc-id "$VPC_ID" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
APP_SG=$(aws ec2 create-security-group --group-name "${PREFIX}-app-sg" --description "App HTTP only from ALB SG" \
  --vpc-id "$VPC_ID" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$APP_SG" --protocol tcp --port 80 --source-group "$ALB_SG" >/dev/null
save_state ALB_SG "$ALB_SG"; save_state APP_SG "$APP_SG"

log "Launch Template ${PREFIX}-app-lt"
UD_B64=$(base64 -w0 "$ROOT/userdata/web-userdata.sh")
cat > /tmp/lt.json <<JSON
{
  "ImageId": "$AMI_ID",
  "InstanceType": "t3.micro",
  "SecurityGroupIds": ["$APP_SG"],
  "IamInstanceProfile": {"Name": "${PREFIX}-ec2-ssm-role"},
  "MetadataOptions": {"HttpTokens": "required"},
  "UserData": "$UD_B64"
}
JSON
aws ec2 create-launch-template --launch-template-name "${PREFIX}-app-lt" \
  --version-description "v1 nginx web app" --launch-template-data file:///tmp/lt.json >/dev/null

log "Target Group（HTTP:80，健康檢查 /）"
TG_ARN=$(aws elbv2 create-target-group --name "${PREFIX}-app-tg" --protocol HTTP --port 80 \
  --vpc-id "$VPC_ID" --target-type instance --health-check-path / \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
save_state TG_ARN "$TG_ARN"

log "Internet-facing ALB（放在兩個公有子網路，掛 ALB SG）"
ALB_ARN=$(aws elbv2 create-load-balancer --name "${PREFIX}-app-alb" --type application --scheme internet-facing \
  --subnets "$PUB1" "$PUB2" --security-groups "$ALB_SG" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)
save_state ALB_ARN "$ALB_ARN"
aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 \
  --default-actions "Type=forward,TargetGroupArn=$TG_ARN" >/dev/null

log "Auto Scaling Group（私有子網路，min 2 / desired 2 / max 4，連接現有目標群組，EC2+ELB 健康檢查，寬限期 300 秒）"
aws autoscaling create-auto-scaling-group --auto-scaling-group-name "${PREFIX}-app-asg" \
  --launch-template "LaunchTemplateName=${PREFIX}-app-lt,Version=\$Default" \
  --min-size 2 --max-size 4 --desired-capacity 2 \
  --vpc-zone-identifier "$PRI1,$PRI2" \
  --target-group-arns "$TG_ARN" --health-check-type ELB --health-check-grace-period 300

log "目標追蹤擴展政策 Target Tracking Policy：平均 CPU 50%（與主控台預設名稱相同）"
aws autoscaling put-scaling-policy --auto-scaling-group-name "${PREFIX}-app-asg" \
  --policy-name "Target Tracking Policy" --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{"PredefinedMetricSpecification":{"PredefinedMetricType":"ASGAverageCPUUtilization"},"TargetValue":50}' >/dev/null

aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"
DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].DNSName' --output text)
save_state ALB_DNS "$DNS"
log "等待目標健康（約 3–5 分鐘）"
for i in $(seq 1 30); do
  H=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
      --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text)
  [ "$H" -ge 2 ] && break; sleep 20
done
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' --output table
log "負載平衡測試：http://$DNS/"
for i in 1 2 3 4 5 6; do curl -s "http://$DNS/"; echo; done

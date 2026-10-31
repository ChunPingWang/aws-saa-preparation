#!/usr/bin/env bash
# Lab 7：SNS Topic + CloudWatch Alarm（ASG 平均 CPU > 70% 連續 1 個 5 分鐘週期）
source "$(dirname "$0")/00-env.sh"

log "建立 SNS Standard Topic ${PREFIX}-alerts"
TOPIC_ARN=$(aws sns create-topic --name "${PREFIX}-alerts" --query TopicArn --output text)
save_state TOPIC_ARN "$TOPIC_ARN"

# 若要收 Email，取消下一行註解並換成自己的信箱，再到信箱點擊確認連結
# aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint you@example.com

log "建立 CloudWatch Alarm ${PREFIX}-asg-high-cpu"
aws cloudwatch put-metric-alarm --alarm-name "${PREFIX}-asg-high-cpu" \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --dimensions Name=AutoScalingGroupName,Value="${PREFIX}-app-asg" \
  --statistic Average --period 300 --evaluation-periods 1 \
  --threshold 70 --comparison-operator GreaterThanThreshold \
  --alarm-actions "$TOPIC_ARN"

log "手動把警示狀態設為 ALARM，驗證通知流程（不影響實際指標）"
aws cloudwatch set-alarm-state --alarm-name "${PREFIX}-asg-high-cpu" \
  --state-value ALARM --state-reason "SAA lab manual test"
aws cloudwatch describe-alarms --alarm-names "${PREFIX}-asg-high-cpu" \
  --query 'MetricAlarms[0].[AlarmName,StateValue,Threshold]' --output table

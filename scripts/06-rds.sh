#!/usr/bin/env bash
# Lab 6：RDS for MySQL Multi-AZ（私有子網路、密碼交給 Secrets Manager 管理）+ 強制容錯移轉
source "$(dirname "$0")/00-env.sh"

log "DB SG：3306 只允許來自 App SG"
DB_SG=$(aws ec2 create-security-group --group-name "${PREFIX}-db-sg" --description "MySQL only from app SG" \
  --vpc-id "$VPC_ID" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$DB_SG" --protocol tcp --port 3306 --source-group "$APP_SG" >/dev/null
save_state DB_SG "$DB_SG"

log "DB Subnet Group（只放私有子網路）"
aws rds create-db-subnet-group --db-subnet-group-name "${PREFIX}-db-subnets" \
  --db-subnet-group-description "SAA lab private subnets" --subnet-ids "$PRI1" "$PRI2" >/dev/null

log "建立 Multi-AZ DB instance（db.t3.micro、gp3 20GiB、不公開、密碼由 Secrets Manager 管理）"
# 對照主控台要改的預設值：引擎 MySQL（主控台預設 Aurora PostgreSQL）、db.t3.micro（預設 db.m7g.large）、
# gp3 20 GiB（預設 200 GiB）、不設 --max-allocated-storage＝關閉儲存自動擴展、
# 不設 --monitoring-interval＝關閉 Enhanced Monitoring、備份保留 1 天、關閉刪除保護
aws rds create-db-instance --db-instance-identifier "${PREFIX}-lab-mysql" \
  --engine mysql --db-instance-class db.t3.micro \
  --allocated-storage 20 --storage-type gp3 \
  --master-username admin --manage-master-user-password \
  --db-name saalab --multi-az --no-publicly-accessible \
  --vpc-security-group-ids "$DB_SG" --db-subnet-group-name "${PREFIX}-db-subnets" \
  --backup-retention-period 1 --no-deletion-protection >/dev/null
echo "建立中，約 10–15 分鐘..."
aws rds wait db-instance-available --db-instance-identifier "${PREFIX}-lab-mysql"

aws rds describe-db-instances --db-instance-identifier "${PREFIX}-lab-mysql" \
  --query 'DBInstances[0].{Status:DBInstanceStatus,MultiAZ:MultiAZ,AZ:AvailabilityZone,Standby:SecondaryAvailabilityZone,Endpoint:Endpoint.Address,Public:PubliclyAccessible,Secret:MasterUserSecret.SecretArn}' \
  --output table

log "強制容錯移轉（模擬 AZ 故障），觀察事件"
aws rds reboot-db-instance --db-instance-identifier "${PREFIX}-lab-mysql" --force-failover >/dev/null
aws rds wait db-instance-available --db-instance-identifier "${PREFIX}-lab-mysql"
aws rds describe-events --source-identifier "${PREFIX}-lab-mysql" --source-type db-instance --duration 30 \
  --query 'Events[].[Date,Message]' --output table

#!/usr/bin/env bash
# Lab 13：EBS（gp3、快照、跨 AZ 還原）+ AMI + EFS（兩個 AZ 同時掛載）
# 使用預設 VPC；需要 Lab 1 的執行個體設定檔 ${PREFIX}-ec2-ssm-role（已清除時先跑 01-iam.sh）
source "$(dirname "$0")/00-env.sh"

run_ssm() {   # run_ssm INSTANCE_ID 'shell commands' → 印出 stdout
  local cid
  cid=$(aws ssm send-command --instance-ids "$1" --document-name AWS-RunShellScript \
        --parameters "$(jq -cn --arg c "$2" '{commands:[$c]}')" --query Command.CommandId --output text)
  aws ssm wait command-executed --command-id "$cid" --instance-id "$1" || true
  aws ssm get-command-invocation --command-id "$cid" --instance-id "$1" --query StandardOutputContent --output text
}

wait_ssm() {  # 等 SSM Agent 註冊上線（Run Command / Session Manager 才能用）
  until [ "$(aws ssm describe-instance-information --filters Key=InstanceIds,Values="$1" \
            --query 'InstanceInformationList[0].PingStatus' --output text)" = Online ]; do sleep 10; done
}

DEF_VPC=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
SUB_A=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$DEF_VPC" Name=availability-zone,Values=us-east-1a --query 'Subnets[0].SubnetId' --output text)
SUB_B=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$DEF_VPC" Name=availability-zone,Values=us-east-1b --query 'Subnets[0].SubnetId' --output text)
save_state DEF_VPC "$DEF_VPC"

log "SG ${PREFIX}-storage-sg：不開任何對外入站；只允許「自己這個 SG」連 NFS 2049（給 EFS）"
STO_SG=$(aws ec2 create-security-group --group-name "${PREFIX}-storage-sg" --vpc-id "$DEF_VPC" \
  --description "SAA lab storage: NFS from self only" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$STO_SG" \
  --ip-permissions "IpProtocol=tcp,FromPort=2049,ToPort=2049,UserIdGroupPairs=[{GroupId=$STO_SG}]" >/dev/null
save_state STO_SG "$STO_SG"

AMI_ID=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
log "啟動 ${PREFIX}-storage-a（us-east-1a）"
INST_A=$(aws ec2 run-instances --image-id "$AMI_ID" --instance-type t3.micro --subnet-id "$SUB_A" \
  --security-group-ids "$STO_SG" --iam-instance-profile Name="${PREFIX}-ec2-ssm-role" \
  --metadata-options HttpTokens=required \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PREFIX}-storage-a}]" \
  --query 'Instances[0].InstanceId' --output text)
save_state INST_A "$INST_A"
aws ec2 wait instance-status-ok --instance-ids "$INST_A"; wait_ssm "$INST_A"

log "EBS：建立 gp3 1 GiB（3000 IOPS / 125 MiB/s 基準免費附帶）並連接為 /dev/sdf"
VOL_A=$(aws ec2 create-volume --availability-zone us-east-1a --volume-type gp3 --size 1 --encrypted \
  --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${PREFIX}-data-vol}]" --query VolumeId --output text)
aws ec2 wait volume-available --volume-ids "$VOL_A"
aws ec2 attach-volume --volume-id "$VOL_A" --instance-id "$INST_A" --device /dev/sdf >/dev/null
aws ec2 wait volume-in-use --volume-ids "$VOL_A"; sleep 10
save_state VOL_A "$VOL_A"
# Nitro 執行個體上 /dev/sdf 會變成 NVMe 裝置；用 SERIAL（= 磁碟區 ID 去掉連字號）找出正確裝置
run_ssm "$INST_A" "DEV=\$(lsblk -dpno NAME,SERIAL | awk '\$2==\"${VOL_A/-/}\"{print \$1}'); mkfs -t xfs \$DEV && mkdir -p /data && mount \$DEV /data && echo \"hello from EBS in us-east-1a \$(date -u +%FT%TZ)\" > /data/hello.txt && sync && cat /data/hello.txt"

log "快照 → 在 us-east-1b 由快照建立新磁碟區（EBS 綁 AZ，快照是區域性的）"
SNAP=$(aws ec2 create-snapshot --volume-id "$VOL_A" --description "${PREFIX} data snapshot" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=${PREFIX}-data-snap}]" --query SnapshotId --output text)
aws ec2 wait snapshot-completed --snapshot-ids "$SNAP"
VOL_B=$(aws ec2 create-volume --availability-zone us-east-1b --snapshot-id "$SNAP" --volume-type gp3 \
  --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${PREFIX}-data-vol-b}]" --query VolumeId --output text)
save_state SNAP "$SNAP"; save_state VOL_B "$VOL_B"

log "AMI：由 ${PREFIX}-storage-a 建立映像（只含根磁碟區；--no-reboot 會有一致性風險）"
IMG=$(aws ec2 create-image --instance-id "$INST_A" --name "${PREFIX}-storage-ami" \
  --block-device-mappings '[{"DeviceName":"/dev/sdf","NoDevice":""}]' --query ImageId --output text)
aws ec2 wait image-available --image-ids "$IMG"
save_state IMG "$IMG"

log "由 AMI 在 us-east-1b 啟動 ${PREFIX}-storage-b，並連接還原的磁碟區"
INST_B=$(aws ec2 run-instances --image-id "$IMG" --instance-type t3.micro --subnet-id "$SUB_B" \
  --security-group-ids "$STO_SG" --iam-instance-profile Name="${PREFIX}-ec2-ssm-role" \
  --metadata-options HttpTokens=required \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PREFIX}-storage-b}]" \
  --query 'Instances[0].InstanceId' --output text)
save_state INST_B "$INST_B"
aws ec2 wait instance-status-ok --instance-ids "$INST_B"; wait_ssm "$INST_B"
aws ec2 attach-volume --volume-id "$VOL_B" --instance-id "$INST_B" --device /dev/sdf >/dev/null
aws ec2 wait volume-in-use --volume-ids "$VOL_B"; sleep 10
run_ssm "$INST_B" "DEV=\$(lsblk -dpno NAME,SERIAL | awk '\$2==\"${VOL_B/-/}\"{print \$1}'); mkdir -p /data && mount \$DEV /data && cat /data/hello.txt"

log "EFS：區域性（多 AZ）檔案系統 + 兩個掛載目標"
FS_ID=$(aws efs create-file-system --performance-mode generalPurpose --throughput-mode elastic --encrypted \
  --tags Key=Name,Value="${PREFIX}-efs" --query FileSystemId --output text)
save_state FS_ID "$FS_ID"
until [ "$(aws efs describe-file-systems --file-system-id "$FS_ID" --query 'FileSystems[0].LifeCycleState' --output text)" = available ]; do sleep 5; done
for s in "$SUB_A" "$SUB_B"; do
  aws efs create-mount-target --file-system-id "$FS_ID" --subnet-id "$s" --security-groups "$STO_SG" >/dev/null
done
until [ "$(aws efs describe-mount-targets --file-system-id "$FS_ID" --query "length(MountTargets[?LifeCycleState=='available'])")" = 2 ]; do sleep 10; done

# 用 AZ 專屬 DNS 名稱（Lab 13 實測：掛載目標建立中就查詢通用名稱，失敗結果會被快取一段時間）
EFS_A="us-east-1a.${FS_ID}.efs.${AWS_REGION}.amazonaws.com"
EFS_B="us-east-1b.${FS_ID}.efs.${AWS_REGION}.amazonaws.com"
OPTS='nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport'
run_ssm "$INST_A" "mkdir -p /efs && mount -t nfs4 -o $OPTS $EFS_A:/ /efs && echo written-by-a-in-1a > /efs/shared.txt && ls -l /efs"
run_ssm "$INST_B" "mkdir -p /efs && mount -t nfs4 -o $OPTS $EFS_B:/ /efs && cat /efs/shared.txt && df -h /efs"

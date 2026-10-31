#!/usr/bin/env bash
# Lab 1：IAM 群組、使用者、EC2 角色（SSM）
source "$(dirname "$0")/00-env.sh"

log "建立群組 ${PREFIX}-developers 並附加唯讀政策（最小權限示範）"
aws iam create-group --group-name "${PREFIX}-developers" >/dev/null
for p in AmazonEC2ReadOnlyAccess AmazonS3ReadOnlyAccess; do
  aws iam attach-group-policy --group-name "${PREFIX}-developers" \
    --policy-arn "arn:aws:iam::aws:policy/$p"
done

log "建立使用者 ${PREFIX}-lab-user（不給主控台密碼、不給存取金鑰）"
aws iam create-user --user-name "${PREFIX}-lab-user" >/dev/null
aws iam add-user-to-group --user-name "${PREFIX}-lab-user" --group-name "${PREFIX}-developers"

log "建立 EC2 角色 ${PREFIX}-ec2-ssm-role（信任 ec2.amazonaws.com）"
aws iam create-role --role-name "${PREFIX}-ec2-ssm-role" \
  --assume-role-policy-document "file://$(dirname "$0")/../policies/ec2-trust-policy.json" >/dev/null
aws iam attach-role-policy --role-name "${PREFIX}-ec2-ssm-role" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

log "建立 Instance Profile 並放入角色（EC2 透過 Instance Profile 取得角色）"
aws iam create-instance-profile --instance-profile-name "${PREFIX}-ec2-ssm-role" >/dev/null
aws iam add-role-to-instance-profile --instance-profile-name "${PREFIX}-ec2-ssm-role" \
  --role-name "${PREFIX}-ec2-ssm-role"

log "驗證"
aws iam list-attached-group-policies --group-name "${PREFIX}-developers" --output table
aws iam get-role --role-name "${PREFIX}-ec2-ssm-role" --query 'Role.AssumeRolePolicyDocument' --output json

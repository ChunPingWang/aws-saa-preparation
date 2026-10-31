#!/bin/bash
# EC2 User Data：安裝 nginx，首頁顯示 Instance ID 與 AZ（用 IMDSv2 取得中繼資料）
dnf install -y nginx
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
echo "<h1>SAA Lab - $IID ($AZ)</h1>" > /usr/share/nginx/html/index.html
systemctl enable --now nginx

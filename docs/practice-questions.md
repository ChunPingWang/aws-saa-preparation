# SAA-C03 模擬練習題（對應 Lab 1–16）

> 題目為作者依考試指南範圍自行撰寫的情境題，用來檢查 Lab 觀念，**不是官方考題**。
> 建議先作答，再展開解析。

---

### Q1（Lab 1｜安全）
一家公司有 40 位開發人員需要相同的 EC2 唯讀權限，且人員經常異動。最容易維護的做法是？

- A. 為每位使用者附加 `AmazonEC2ReadOnlyAccess`
- B. 建立 IAM 群組並附加 `AmazonEC2ReadOnlyAccess`，將使用者加入群組
- C. 建立 IAM 角色並讓所有人共用同一組 Access Key
- D. 在 SCP 中允許 `ec2:Describe*`

<details><summary>答案與解析</summary>

**B**。權限掛在群組，人員異動只需調整群組成員。C 共用金鑰違反最佳實務；D 的 SCP 只限制上限、不授予權限。
</details>

### Q2（Lab 1、3｜安全）
EC2 上的應用程式需要讀取 S3。哪個方式最安全？

- A. 把 Access Key 寫在環境變數
- B. 把 Access Key 存在 User Data
- C. 建立 IAM 角色並透過 Instance Profile 附加到 EC2
- D. 將 Bucket 設為公開讀取

<details><summary>答案與解析</summary>

**C**。角色提供自動輪替的臨時憑證，程式碼不需要長期金鑰。
</details>

### Q3（Lab 2｜彈性／成本）
私有子網路中的 EC2 每天從 S3 下載數 TB 資料，目前經由 NAT Gateway，費用很高。如何在不暴露到網際網路的情況下降低成本？

- A. 把 EC2 移到公有子網路
- B. 建立 S3 Gateway VPC Endpoint 並加入私有路由表
- C. 建立 S3 Interface Endpoint
- D. 增加第二個 NAT Gateway

<details><summary>答案與解析</summary>

**B**。Gateway Endpoint 免費，流量不經 NAT。C 也可行但有每小時與每 GB 費用。
</details>

### Q4（Lab 2｜彈性）
架構有兩個 AZ，但只有一個 NAT Gateway。若該 AZ 故障會發生什麼事？如何改善？

- A. 不影響，NAT Gateway 是區域服務
- B. 另一個 AZ 的私有子網路會失去對外連線；應在每個 AZ 建立 NAT，並讓各 AZ 路由表指向自己的 NAT
- C. 改用 Internet Gateway 即可
- D. 改用 VPC Peering

<details><summary>答案與解析</summary>

**B**。Zonal NAT Gateway 綁定單一 AZ（AWS 另有 Regional NAT 新選項，但考試仍以此觀念為主）。
</details>

### Q5（Lab 3｜安全）
資安規範禁止開放 22 port，但維運人員需要登入 Linux EC2 並保留操作紀錄。最佳做法？

- A. 建立 Bastion Host
- B. 開放 22 給公司 IP
- C. 使用 Systems Manager Session Manager，EC2 附加 `AmazonSSMManagedInstanceCore` 角色
- D. 使用 EC2 序列主控台

<details><summary>答案與解析</summary>

**C**。不需任何傳入 port，連線可記錄到 S3/CloudWatch Logs。
</details>

### Q6（Lab 3｜安全）
需要封鎖某個惡意 IP 存取整個子網路。應使用？

- A. Security Group 新增 Deny 規則
- B. Network ACL 新增 Deny 規則
- C. IAM Policy
- D. Route Table

<details><summary>答案與解析</summary>

**B**。Security Group 只有 Allow；NACL 可 Deny，且作用在子網路層級。
</details>

### Q7（Lab 4｜彈性）
Web 層的 nginx 偶爾當掉，但 EC2 本身仍在執行，Auto Scaling 沒有替換它。怎麼修正？

- A. 把 ASG 的健康檢查類型加上 ELB
- B. 改用更大的執行個體
- C. 啟用 Detailed Monitoring
- D. 增加 Desired Capacity

<details><summary>答案與解析</summary>

**A**。預設只看 EC2 狀態檢查；加上 ELB 健康檢查後，目標不健康就會被替換。
</details>

### Q8（Lab 4｜安全）
App 層 EC2 只應接受來自 ALB 的流量，且 ALB 節點 IP 會變動。如何設定？

- A. App SG 允許 ALB 子網路 CIDR
- B. App SG 的來源設定為 ALB 的 Security Group ID
- C. 在 NACL 允許 0.0.0.0/0
- D. 給 ALB 配 Elastic IP

<details><summary>答案與解析</summary>

**B**。SG 參照 SG，不受 IP 變動影響。ALB 也不能配 Elastic IP（NLB 才可以）。
</details>

### Q9（Lab 4｜高效能）
遊戲伺服器使用 UDP，需要超低延遲與固定 IP 給客戶端白名單。應使用？

- A. ALB
- B. NLB
- C. CloudFront
- D. API Gateway

<details><summary>答案與解析</summary>

**B**。NLB 支援 TCP/UDP，每個 AZ 可配 Elastic IP。
</details>

### Q10（Lab 5｜成本）
日誌檔前 30 天常被查詢，之後偶爾查詢，一年後只為合規保存 7 年且很少取回。最省錢的生命週期？

- A. Standard → Standard-IA（30 天）→ Glacier Deep Archive（365 天）
- B. 全部放 Standard
- C. Standard → One Zone-IA（1 天）
- D. 全部放 Intelligent-Tiering 並關閉生命週期

<details><summary>答案與解析</summary>

**A**。Deep Archive 最便宜，適合長期合規保存。
</details>

### Q11（Lab 5｜安全）
法規要求某些物件在 5 年內不可被任何人（含 root）修改或刪除。應使用？

- A. 版本控制
- B. MFA Delete
- C. S3 Object Lock（Compliance mode）
- D. Bucket Policy Deny DeleteObject

<details><summary>答案與解析</summary>

**C**。Compliance mode 下，保留期內任何人都不能刪除或縮短保留期。
</details>

### Q12（Lab 6｜彈性）
RDS MySQL 必須在單一 AZ 故障時自動恢復，且應用程式不需修改連線字串。應啟用？

- A. Read Replica
- B. Multi-AZ
- C. 每小時手動快照
- D. 跨區域備份複寫

<details><summary>答案與解析</summary>

**B**。同步待命，容錯移轉後端點不變（Lab 6 實測約 35 秒）。
</details>

### Q13（Lab 6｜高效能）
報表查詢拖慢了 RDS 主資料庫。如何在不影響寫入的情況下分擔？

- A. Multi-AZ 待命執行個體
- B. Read Replica，報表連到 Replica 的端點
- C. 加大執行個體
- D. ElastiCache 寫入快取

<details><summary>答案與解析</summary>

**B**。Multi-AZ「執行個體」部署的待命不可讀；Read Replica 才是用來分擔讀取。
</details>

### Q14（Lab 6、12｜安全）
資料庫密碼不能寫在程式碼中，且需要每 30 天自動輪替。應使用？

- A. SSM Parameter Store SecureString
- B. Secrets Manager
- C. KMS
- D. 環境變數

<details><summary>答案與解析</summary>

**B**。Secrets Manager 原生支援輪替；RDS 還能直接以 `--manage-master-user-password` 託管。
</details>

### Q15（Lab 7｜監控）
需要在 EC2 記憶體使用率超過 80% 時告警。首先要做什麼？

- A. 啟用 Detailed Monitoring
- B. 安裝 CloudWatch Agent 推送記憶體指標
- C. 啟用 CloudTrail
- D. 啟用 VPC Flow Logs

<details><summary>答案與解析</summary>

**B**。記憶體與磁碟使用率不在 EC2 預設指標中。
</details>

### Q16（Lab 8｜成本）
新產品流量完全無法預測，可能長時間為 0，偶爾暴增。DynamoDB 應選？

- A. 佈建容量
- B. 隨需容量
- C. 佈建容量 + 保留容量
- D. DAX

<details><summary>答案與解析</summary>

**B**。依請求計費，無需容量規劃。
</details>

### Q17（Lab 8｜彈性）
數千個 Lambda 同時連線 RDS，造成連線數耗盡。應如何改善？

- A. 增加 Lambda 記憶體
- B. 使用 RDS Proxy
- C. 改用 Multi-AZ
- D. 增加 Read Replica

<details><summary>答案與解析</summary>

**B**。RDS Proxy 提供連線池。
</details>

### Q18（Lab 9｜安全）
靜態網站放在 S3，要求只能經由 CloudFront 存取，不能直接存取 S3 URL。應使用？

- A. 將 Bucket 設為公開，並在 CloudFront 啟用 HTTPS
- B. CloudFront Origin Access Control + Bucket Policy 限定該 Distribution
- C. S3 靜態網站託管端點 + WAF
- D. Presigned URL

<details><summary>答案與解析</summary>

**B**。Lab 9 實測：CloudFront 回 200、直連 S3 回 403。
</details>

### Q19（Lab 10｜彈性）
要讓 `example.com`（網域根）指向 ALB。應建立？

- A. CNAME 記錄
- B. Alias A 記錄
- C. MX 記錄
- D. PTR 記錄

<details><summary>答案與解析</summary>

**B**。CNAME 不能用在 zone apex；Alias 可以，且查詢 AWS 資源免費。
</details>

### Q20（Lab 10｜彈性）
主站在 us-east-1、備援在 us-west-2，主站故障時自動把 DNS 切到備援。應使用？

- A. Weighted routing
- B. Failover routing + Health Check
- C. Geolocation routing
- D. Multivalue answer

<details><summary>答案與解析</summary>

**B**。
</details>

### Q21（Lab 11｜解耦）
訂單建立後，需同時通知庫存、出貨、帳務三個服務，每個服務獨立處理且可暫時離線。最佳設計？

- A. 應用程式依序呼叫三個 API
- B. SNS 主題扇出到三個 SQS 佇列，各服務從自己的佇列讀取
- C. 單一 SQS 佇列，三個服務共同讀取
- D. Kinesis Data Firehose

<details><summary>答案與解析</summary>

**B**。C 的同一則訊息只會被其中一個消費者處理。
</details>

### Q22（Lab 11｜解耦）
訂單事件必須依客戶維持處理順序，且不可重複處理。應使用？

- A. SQS Standard
- B. SQS FIFO，以客戶 ID 作為 MessageGroupId
- C. SNS Standard
- D. EventBridge

<details><summary>答案與解析</summary>

**B**。
</details>

### Q23（Lab 12｜安全）
要加密 2 GB 的檔案，並由公司控管金鑰的使用權限與稽核紀錄。正確做法？

- A. 直接用 KMS Encrypt API 加密整個檔案
- B. 用 KMS `GenerateDataKey` 取得資料金鑰，在本地加密檔案（Envelope Encryption）
- C. 用 CloudHSM 直接上傳檔案
- D. 用 ACM 加密

<details><summary>答案與解析</summary>

**B**。KMS Encrypt 單次上限 4 KB。
</details>

### Q24（綜合｜成本）
批次影像處理工作可以隨時中斷並重試，希望成本最低。運算應選？

- A. On-Demand
- B. Reserved Instances
- C. Spot Instances
- D. Dedicated Hosts

<details><summary>答案與解析</summary>

**C**。
</details>

### Q25（綜合｜彈性）
要求 RPO/RTO 數分鐘、成本中等的跨區域災難復原策略？

- A. Backup & Restore
- B. Pilot Light
- C. Warm Standby
- D. Multi-Site Active/Active

<details><summary>答案與解析</summary>

**C**。Warm Standby 在備援區保持縮小規模的完整環境，切換時擴容即可。Pilot Light 只保留核心（如資料庫複寫），RTO 較長；Active/Active 成本最高。
</details>

---

## v3 新增（Lab 13–16）

### Q26（Lab 13｜彈性）
us-east-1a 的 EC2 掛著一顆 500 GiB 的 gp3 資料磁碟區，現在要把這台工作負載搬到 us-east-1c。最直接的做法是？

- A. 卸離磁碟區，直接連接到 us-east-1c 的新執行個體
- B. 對磁碟區建立快照，在 us-east-1c 由快照建立磁碟區並連接
- C. 開啟 EBS Multi-Attach
- D. 把磁碟區類型改成 io2

<details><summary>答案與解析</summary>

**B**。EBS 磁碟區綁定單一 AZ，只能連接同 AZ 的執行個體；快照是區域性的，可在任何 AZ 還原（Lab 13 Step 13-8）。Multi-Attach 也只限同 AZ。
</details>

### Q27（Lab 13｜效能）
多台分散在三個 AZ 的 Linux Web 伺服器需要同時讀寫同一批使用者上傳檔案，且容量會持續成長。最適合的儲存？

- A. 每台各掛一顆 EBS，用 rsync 同步
- B. Instance Store
- C. Amazon EFS（區域性）
- D. FSx for Windows File Server

<details><summary>答案與解析</summary>

**C**。EFS 是 NFS、區域性、可跨 AZ 同時掛載、自動擴展容量（Lab 13 Step 13-17）。FSx for Windows 是 SMB，適合 Windows。
</details>

### Q28（Lab 13｜安全）
公司要求所有 EBS 都必須加密，但有一顆既有的未加密磁碟區。如何在最少停機下改為加密？

- A. 在磁碟區上直接勾選「加密」
- B. 建立快照 → 複製快照並啟用加密 → 由加密快照建立新磁碟區 → 替換
- C. 開啟帳戶層級的 EBS 預設加密，既有磁碟區會自動加密
- D. 用 KMS 的 ReEncrypt API

<details><summary>答案與解析</summary>

**B**。既有磁碟區無法直接改成加密；預設加密只影響之後新建的磁碟區。
</details>

### Q29（Lab 14｜安全）
安全團隊發現某個 IP 範圍正在掃描公有子網路中的所有執行個體，需要立即在子網路層級封鎖該範圍。應使用？

- A. Security Group 加入 Deny 規則
- B. Network ACL 加入編號較小的 Deny 規則
- C. 路由表加入黑洞路由
- D. VPC Flow Logs

<details><summary>答案與解析</summary>

**B**。SG 只能 Allow；NACL 可以 Deny，依規則編號由小到大比對（Lab 14 Step 14-11）。Flow Logs 只記錄、不阻擋。
</details>

### Q30（Lab 14｜彈性）
VPC-A 與 VPC-B、VPC-B 與 VPC-C 各自建立了 VPC Peering。VPC-A 的執行個體無法連到 VPC-C，原因是？

- A. 需要在 VPC-B 啟用 IP 轉送
- B. VPC Peering 不支援遞移路由，需要 A–C 直接 Peering 或改用 Transit Gateway
- C. VPC-C 的 SG 沒有允許 VPC-B 的 CIDR
- D. Peering 只支援同一個 AZ

<details><summary>答案與解析</summary>

**B**。Peering 是一對一、不可遞移；VPC 數量多時用 Transit Gateway。
</details>

### Q31（Lab 14｜安全）
SG 允許 ICMP，但 ping 不通；Flow Logs 顯示 REJECT。最可能的原因？

- A. 執行個體沒有公有 IP
- B. 子網路的 NACL 拒絕了該流量（或沒有允許回應方向）
- C. 沒有 IAM 角色
- D. Flow Logs 的篩選設成 REJECT

<details><summary>答案與解析</summary>

**B**。NACL 無狀態，進出方向都要允許；SG 有狀態。Lab 14 Step 14-13、14-14 實測。
</details>

### Q32（Lab 15｜效能／成本）
行動 App 的後端 API 要提供合作夥伴使用，需依合作夥伴分別限制每秒請求數與每日配額，並以 API 金鑰識別。應使用？

- A. Application Load Balancer + Lambda
- B. API Gateway HTTP API
- C. API Gateway REST API 搭配用量計畫與 API 金鑰
- D. Lambda 函式 URL

<details><summary>答案與解析</summary>

**C**。用量計畫（Usage Plans）與 API 金鑰是 REST API 的功能；超量回 429。
</details>

### Q33（Lab 15｜彈性）
訂單建立後需依序執行：信用檢查 → 若金額大於 10 萬等待人工核准（可能數天）→ 扣庫存 → 通知；每一步失敗要自動重試並保留執行紀錄。最少營運負擔的方案？

- A. 一支 Lambda 依序呼叫
- B. SQS 串接多個 Lambda
- C. Step Functions 標準工作流程（Choice + waitForTaskToken + Retry）
- D. Step Functions 快速工作流程

<details><summary>答案與解析</summary>

**C**。標準工作流程可執行最長 1 年、內建重試與執行歷史；快速工作流程上限 5 分鐘。Lambda 最長 15 分鐘。
</details>

### Q34（Lab 15｜解耦）
多個微服務要訂閱「訂單建立」事件，但每個服務只關心特定條件（例如某些地區、金額區間），也要能接收 SaaS 合作夥伴送來的事件。最適合？

- A. SNS 標準主題
- B. Amazon EventBridge 事件匯流排 + 規則的事件模式
- C. Kinesis Data Streams
- D. SQS FIFO

<details><summary>答案與解析</summary>

**B**。EventBridge 依事件內容路由、支援合作夥伴事件來源與 Archive/Replay（Lab 15 Step 15-15、15-19：不符合模式的事件不會觸發）。
</details>

### Q35（Lab 16｜安全）
稽核人員要知道「上週是誰刪除了生產環境的 S3 Bucket」。應查詢？

- A. AWS Config 資源時程
- B. AWS CloudTrail
- C. VPC Flow Logs
- D. CloudWatch Metrics

<details><summary>答案與解析</summary>

**B**。CloudTrail 記錄 API 呼叫的身分、時間、來源 IP。Config 記錄資源組態的變化與合規狀態，兩者互補（Lab 16 Step 16-2）。
</details>

### Q36（Lab 16｜安全）
公司要持續偵測所有允許 0.0.0.0/0 存取 SSH 的 Security Group，並自動移除該規則。最少營運負擔的方式？

- A. 每天用 Lambda 掃描所有 SG
- B. AWS Config 受管規則 restricted-ssh + SSM Automation 自動修補
- C. GuardDuty
- D. 用 SCP 禁止建立 SG

<details><summary>答案與解析</summary>

**B**。Config 規則偵測、SSM Automation 修補。SCP 是預防，但無法精準到「規則內容」且會擋掉所有 SG 操作。
</details>

### Q37（Lab 16｜成本）
資料湖在 S3 存了數 TB 的 CSV 日誌，分析師偶爾用 Athena 查詢，費用偏高。最有效的降本方式？

- A. 改用 S3 Glacier Deep Archive
- B. 轉成 Parquet 並依日期分割、壓縮，查詢時帶分割區條件
- C. 把 Athena 換成 RDS
- D. 增加 Athena 工作群組數量

<details><summary>答案與解析</summary>

**B**。Athena 依掃描量計費；欄式格式 + 分割區 + 壓縮大幅降低掃描量。Glacier 的資料不能直接用 Athena 查。
</details>

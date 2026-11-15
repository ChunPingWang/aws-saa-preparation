# AWS SAA-C03 觀念釐清

> 本文件整理準備 SAA-C03 時逐一提問的觀念，作為《SAA-C03 考題詳解》與《SAA-C03 產品概念地圖》的補充。每個主題包含功能說明、使用情境、容易混淆的地方，以及對應的考題題號，可以回到詳解文件練習。
>
> 文中的價格皆為 us-east-1 的參考值，各 Region 不同，AWS 也會調整，請以官方價目表為準。

## 目錄

1. [AWS Config 與 Config Rules](#1-aws-config-與-config-rules)
2. [S3 Glacier Deep Archive](#2-s3-glacier-deep-archive)
3. [S3 Infrequent Access（Standard-IA 與 One Zone-IA）](#3-s3-infrequent-accessstandard-ia-與-one-zone-ia)
4. [RPO 與 RTO](#4-rpo-與-rto)
5. [Elastic Load Balancing（ALB、NLB、GWLB、CLB）](#5-elastic-load-balancingalbnlbgwlbclb)
6. [AWS Network Firewall](#6-aws-network-firewall)
7. [Amazon Cognito（User Pool 與 Identity Pool）](#7-amazon-cognitouser-pool-與-identity-pool)
8. [RDS Performance Insights](#8-rds-performance-insights)
9. [資源標籤治理與 AWS Config required-tags](#9-資源標籤治理與-aws-config-required-tags)
10. [Kinesis、DynamoDB、Lambda 的關係與使用情境](#10-kinesisdynamodblambda-的關係與使用情境)
11. [Amazon Redshift](#11-amazon-redshift)
12. [AWS 資料庫服務總比較](#12-aws-資料庫服務總比較)
13. [AWS Config、CloudTrail、CloudWatch 的關係](#13-aws-configcloudtrailcloudwatch-的關係)

---

## 1. AWS Config 與 Config Rules

### 一句話定位

AWS 帳號裡的「資源組態紀錄器＋合規稽核員」。它回答三個問題：

1. **我有哪些資源？**（盤點）
2. **這些資源的設定怎麼變過？**（組態歷史）
3. **現在的設定合不合規？**（規則評估）

### 核心功能

| 功能 | 說明 |
|---|---|
| Configuration recorder | 持續記錄支援的資源（EC2、SG、S3、IAM、RDS…）的設定，每次變更都產生一筆組態項目（configuration item）。可以選擇持續記錄或每日定期記錄，後者比較省錢 |
| 組態歷史與時間軸 | 可以看到某個資源在任一時間點的設定，以及它和其他資源的關係（例如 EC2 掛了哪個 SG、在哪個 subnet）。歷史存到 S3，變更通知可以送到 SNS |
| Config Rules | 持續評估資源是否合規。有數百條 AWS 受管規則，也可以用 Lambda 或 Guard 語法寫自訂規則。評估可以在設定變更時觸發，也可以定期觸發 |
| 自動修復（Remediation） | 不合規時呼叫 Systems Manager Automation runbook 修正，例如關閉公開的 S3、移除 0.0.0.0/0 的 SSH 規則 |
| Conformance Packs | 把一組規則加上修復動作打包部署，例如 CIS、PCI DSS、NIST 範本，可以部署到整個組織 |
| Aggregator | 把多帳號、多 Region 的組態與合規結果集中到一個帳號檢視 |
| Advanced Query | 用類 SQL 查詢目前的資源組態，例如「列出所有沒加密的 EBS volume」 |

### Config Rules 深入說明

AWS Config 本身只負責記錄設定；**Config Rules 才負責判斷設定對不對**。兩者的關係：

```
資源設定變更 ──► Configuration recorder ──► 組態項目（CI）
                                                │
                                                ▼
                                   Config Rule 評估（變更觸發／定期觸發）
                                                │
                     ┌──────────────────────────┼──────────────────────────┐
                     ▼                          ▼                          ▼
                COMPLIANT                 NON_COMPLIANT          （EventBridge 事件）
                                                │                          │
                                                ▼                          ▼
                                   Remediation（SSM Automation）     SNS 通知／Lambda
```

**規則的三種來源**

| 類型 | 說明 | 例子 |
|---|---|---|
| **AWS 受管規則** | AWS 預先寫好的規則，只要設定參數就能用，數量有數百條 | `encrypted-volumes`、`required-tags`、`restricted-ssh`、`s3-bucket-public-read-prohibited`、`cloudtrail-enabled`、`root-account-mfa-enabled`、`rds-multi-az-support` |
| **自訂 Lambda 規則** | 自己寫 Lambda 函數判斷，彈性最大但要自己維護程式 | 檢查 EC2 是否使用公司核准的 AMI 清單以外的特殊邏輯 |
| **自訂 Guard 規則** | 用 CloudFormation Guard 的宣告式語法撰寫，不需要寫 Lambda | 簡單的屬性檢查，例如某個欄位必須為 true |

**觸發方式**

| 觸發 | 說明 | 適用 |
|---|---|---|
| 組態變更觸發 | 符合範圍（資源類型、標籤、資源 ID）的資源一變更就評估 | 例如 SG 一被修改就檢查是否開放 0.0.0.0/0 的 SSH |
| 定期觸發 | 每 1、3、6、12 或 24 小時評估一次 | 帳號層級的檢查，例如 CloudTrail 是否開啟、root 是否有 MFA |

**評估模式**

- **Detective（偵測，預設）**：評估已經存在的資源。
- **Proactive（主動）**：部分受管規則可以在資源**部署前**評估其設定，例如搭配 CloudFormation hooks。不過它只回報結果，真正阻止部署要靠 hook 或流程。考題中講「預防」時，通常仍以 SCP、IAM policy、Control Tower proactive controls 為主。

**評估結果**：`COMPLIANT`、`NON_COMPLIANT`、`NOT_APPLICABLE`（規則不適用於該資源）、`INSUFFICIENT_DATA`（資料不足，例如還沒有評估過）。

**不合規時能做什麼**

| 動作 | 作法 |
|---|---|
| 通知 | 合規狀態改變時產生 **EventBridge** 事件，再送到 SNS、Lambda 或工單系統 |
| 自動修復 | 規則關聯 **SSM Automation runbook**，可以設成手動執行或自動執行，並設定重試次數。例如 `AWS-DisableS3BucketPublicReadWrite`、移除 SG 中的 0.0.0.0/0 規則 |
| 集中檢視 | Aggregator 匯總多帳號、多 Region 的結果；Security Hub 也會收進來 |

**規模化部署**

- **Organization Config rules**：從管理帳號或委派管理員帳號，把規則一次部署到組織內所有帳號。
- **Conformance Packs**：用一份 YAML 範本把多條規則與修復動作打包成一組（例如 CIS、PCI DSS、NIST 800-53），可以部署到單一帳號或整個組織，結果以合規分數呈現。
- **Control Tower detective controls**：Control Tower 的偵測型 guardrail，底層就是 Config 規則。

**費用重點**：依「規則評估次數」計費，再加上 recorder 記錄的組態項目數。規則越多、資源變動越頻繁，費用越高。

### 使用情境

- **合規稽核**：證明「所有 EBS 都有加密」「S3 都禁止公開存取」「CloudTrail 都有開」，並保留歷史紀錄給稽核人員。
- **標籤治理**：用 required-tags 規則找出沒加成本中心標籤的資源。
- **安全基線監控**：例如 restricted-ssh、iam-password-policy、rds-storage-encrypted，搭配自動修復。
- **變更調查**：出事時回看某個 SG 或路由表在事發前後的設定差異，並對照 CloudTrail 找出是誰改的。
- **組織層級治理**：Control Tower 的 detective guardrails 和 Security Hub 的標準檢查，底層都用 Config 規則。

### 容易混淆的地方

- **Config 和 CloudTrail 回答的問題不同**：Config 回答「設定變成什麼」，CloudTrail 回答「誰在何時呼叫了哪個 API」。題目要「追蹤組態變更＋API 呼叫」就兩個都選（Q34、Q318）；要找「誰改的」就是 CloudTrail（Q395）。
- **Config 是偵測型，不是預防型**：它只能事後發現並修正，不能阻止不合規的動作發生。要預防，用 SCP、IAM policy 或 Control Tower proactive controls（Q151、Q433、Q789、Q887）。
- **它是 Region 級服務**：每個 Region 都要各自啟用，跨帳號、跨 Region 用 aggregator 集中。
- **費用依量計算**：按記錄的組態項目數與規則評估次數計費。資源變動頻繁的環境（例如大量 Auto Scaling）可以改成每日記錄，或排除不需要的資源類型。
- **受管規則優先於自訂規則**：題目要「最少設定、最少維運」時，有現成的受管規則（例如 `encrypted-volumes`、`required-tags`、`restricted-ssh`）就不要選自己寫 Lambda（Q31、Q689、Q774）。
- **Config 和 Trusted Advisor、Inspector 不同**：Trusted Advisor 是定期的最佳實務建議（成本、效能、安全、配額）；Inspector 掃描 EC2、容器映像與 Lambda 的軟體弱點；Config 是持續的組態合規評估（Q26）。
- **預防＋偵測常一起出現**：例如用 IAM policy 只允許建立加密的 EBS（預防），再用 Config 規則找出既有的未加密資源（偵測）（Q682）。若只要「新建的 EBS 都加密」，最簡單的是開啟 EBS encryption by default（Q887）。

### 考試判斷重點

看到「detect / track configuration changes」「compliance」「noncompliant resources」「ensure all resources are tagged/encrypted」，並且要「最少維運」時，答案通常是 **AWS Config 受管規則（＋SNS 通知或 SSM 自動修復）**。

**相關題號**
- 選 AWS Config／Config Rules：Q26、Q31、Q34、Q318、Q512、Q665、Q682、Q689、Q774
- 改選其他服務：Q395（CloudTrail 找出是誰改的）、Q151、Q433、Q789、Q887（預防型控制）

---

## 2. S3 Glacier Deep Archive

### 一句話定位

**S3 最便宜的儲存類別**，專門放「必須保存很久、但幾乎不會再讀」的資料。它用「取回要等 12 小時以上」換來最低的儲存成本。

### 核心特性

| 項目 | 內容 |
|---|---|
| 成本 | 所有 S3 類別中最低，約每 TB 每月 1 美元 |
| 耐久性與可用性 | 11 個 9 的耐久性，跨至少 3 個 AZ 保存，和 S3 Standard 相同 |
| 取回時間 | **Standard：12 小時內**；**Bulk：48 小時內**（更便宜）。**沒有 Expedited**，這點和 Glacier Flexible Retrieval 不同 |
| 最短計費期間 | **180 天**，提前刪除或轉出仍要付滿 180 天 |
| 每個物件的額外費用 | 另外加計約 40 KB 的 metadata 費用（32 KB 以 Deep Archive 費率、8 KB 以 Standard 費率計），大量小檔案不划算 |
| 讀取方式 | 不能直接 GET。要先發 RestoreObject，指定取回速度與暫存天數，完成後產生暫時副本才能讀取 |
| 搭配功能 | Object Lock（WORM）、版本控制、Lifecycle、S3 Batch Operations、CRR |

### 資料怎麼進來

- **Lifecycle 轉換**：最常見，例如「30 天後」或「1 年後」轉 Deep Archive。
- **直接寫入**：上傳時指定 storage class 為 `DEEP_ARCHIVE`。
- **Tape Gateway**：地端備份軟體寫入虛擬磁帶，退出（eject）後的磁帶放到 Deep Archive，取代實體磁帶。
- **Intelligent-Tiering 的 Deep Archive Access 層**：需另外啟用，物件 180 天以上沒被存取時自動移入。

### 適合的使用情境

- **法規長期保存**：金融、醫療、會計紀錄保留 7–10 年以上，平時不讀，只在稽核時取回。可搭配 Object Lock compliance mode 防刪改。
- **取代磁帶庫**：淘汰實體磁帶或異地磁帶保管。
- **媒體與科研原始檔封存**：舊新聞影片母帶、基因或實驗原始資料、已結案專案檔案。
- **備份的最後一層**：近期備份放 Standard 或 IA，較舊版本轉 Deep Archive。
- **事前排定的低頻使用**：例如一年兩次的模型訓練，可提前一兩天取回。

### 不適合的情況

- 需要在 **12 小時內**取回：6 小時內用 Glacier Flexible Retrieval；數分鐘內用 Expedited 或 Glacier Instant Retrieval。
- 需要**立即存取**（即使很少讀）：用 Glacier Instant Retrieval 或 Standard-IA。
- 資料保存不到 180 天：會被收滿 180 天的費用。
- 數百萬個 KB 級小檔案：metadata 費用與 Lifecycle 轉換請求費很高，建議先打包成大檔再封存（Q918）。

### 考試判斷重點

- 「retain for N years」「rarely / never accessed」「lowest cost」，而且可接受 12 小時以上取回或沒提取回時間 → **Deep Archive**。
- 「must be immediately available」「within 6 hours」「within minutes」→ **排除 Deep Archive**。
- Lifecycle 可以直接從 Standard 轉 Deep Archive，不需要先經過 IA 或 Glacier。

**相關題號**
- 選 Deep Archive：Q23、Q53、Q126、Q147、Q215、Q583、Q651、Q673、Q918、Q953、Q956
- 排除 Deep Archive：Q49、Q485、Q551、Q759

---

## 3. S3 Infrequent Access（Standard-IA 與 One Zone-IA）

### 一句話定位

IA 是 Infrequent Access，指**不常存取、但需要時要立即拿得到**的資料。用較低的儲存費，換取讀取時要付費。

### 兩種 IA 的比較

| 項目 | S3 Standard | **Standard-IA** | **One Zone-IA** |
|---|---|---|---|
| 存取延遲 | 毫秒 | **毫秒** | 毫秒 |
| 儲存地點 | ≥3 個 AZ | ≥3 個 AZ | **只在 1 個 AZ** |
| 耐久性 | 11 個 9 | 11 個 9 | 11 個 9（AZ 毀損時資料遺失） |
| 設計可用性 | 99.99% | 99.9% | 99.5% |
| 儲存費用（參考） | 約 $0.023/GB-月 | 約 $0.0125/GB-月（約便宜 45%） | 約 $0.01/GB-月（再便宜約 20%） |
| 讀取費 | 無 | **有，每 GB 計費** | 有 |
| 最短計費期間 | 無 | **30 天** | **30 天** |
| 最小計費物件大小 | 無 | **128 KB** | **128 KB** |

### 計費上要注意的三件事

1. **讀取費**：粗略估算，如果平均每個月會把資料完整讀一次以上，省下的儲存費大約就被讀取費抵掉，留在 Standard 反而划算。
2. **30 天最短期間**：放進去不到 30 天就刪除或轉出仍要付滿 30 天；Lifecycle 也規定物件至少在 Standard 放滿 30 天才能轉 IA。
3. **128 KB 最小計費**：小於 128 KB 一律以 128 KB 計費，目前 Lifecycle 預設也不會把小於 128 KB 的物件轉到 IA。

### 使用情境

**Standard-IA**：不常讀、要立即拿到、不能遺失。

- 備份與 DR 副本：平時不讀，災難時要立即還原。
- 舊資料仍有線上查詢需求：30 天後很少看的報表、交易紀錄、使用者上傳的舊檔案。
- Lifecycle 分層：例如「30 天後轉 Standard-IA，1 年後轉 Glacier」。
- 大型檔案的長尾內容：需求較低但仍要隨點隨播的舊影片（Q759）。

**One Zone-IA**：同上，但**資料可以重建**。

- 可重新產生的資料：縮圖、轉檔副本、處理後的中間結果。
- 第二份副本：地端已有主資料，或 CRR 複寫到另一個 Region 後的副本。
- 不要放「關鍵、無法重建、需要高可用」的資料。

### 和其他類別怎麼分

| 情況 | 選擇 |
|---|---|
| 存取模式**已知**（例如 30 天後少用），要立即可讀且不能遺失 | Standard-IA |
| 同上，但資料可以重建 | One Zone-IA |
| 存取模式**不可預測**或會變 | Intelligent-Tiering（沒有讀取費，自動在各層間移動） |
| 一季甚至更久才讀一次，但仍要立即可讀 | Glacier Instant Retrieval（儲存更便宜、讀取費更高、最短 90 天） |
| 幾乎不讀，可等數小時以上 | Glacier Flexible Retrieval 或 Deep Archive |

### 考試判斷重點

- 「rarely accessed after 30 days」＋「immediately accessible」＋「highly available／resilient」→ **Standard-IA**。
- 「critical」「cannot be recreated」「resilient to AZ loss」「maximize durability」→ **排除 One Zone-IA**。
- 存取模式不可預測時，Standard-IA 可能產生高額讀取費，通常選 Intelligent-Tiering。
- EFS 也有類似的 IA 層（EFS Standard-IA、One Zone-IA），概念相同，以 lifecycle 自動移動不常用的檔案（Q384）。

**相關題號**
- 選 Standard-IA：Q66、Q153、Q250、Q356、Q373、Q606、Q656、Q759
- 排除 One Zone-IA：Q22、Q53、Q66、Q606、Q651、Q890
- 改選 Intelligent-Tiering：Q22、Q469、Q829

---

## 4. RPO 與 RTO

### 定義

| 指標 | 全名 | 回答的問題 | 衡量的是 |
|---|---|---|---|
| **RPO** | Recovery Point Objective | 災難後最多可接受**遺失多久之前的資料**？ | 往回看：最後一個可用的備份或複本距離災難多久 |
| **RTO** | Recovery Time Objective | 災難後最多可接受**停機多久**？ | 往前看：從故障到服務恢復要多久 |

```
   最後一次備份/複寫          災難發生             服務恢復
          │                    │                    │
──────────●────────────────────✖────────────────────●──────→ 時間
          │◄──── RPO ─────────►│◄───── RTO ────────►│
           （這段資料會遺失）     （這段時間服務中斷）
```

**例子**：每天凌晨 2 點備份，下午 2 點機房故障，花 4 小時在另一個 Region 重建。實際 RPO 是 12 小時（凌晨 2 點到下午 2 點的資料遺失），實際 RTO 是 4 小時。

### 兩者由什麼決定

- **RPO 取決於資料複製的頻率與方式**：每日備份約 24 小時；每小時快照約 1 小時；非同步複寫為秒級；同步複寫接近 0。
- **RTO 取決於恢復時要做多少事**：從備份還原並重建基礎設施為小時級；資料庫已在跑只需切換為分鐘級；兩邊同時在服務接近 0。

RPO 和 RTO 越小成本越高，所以要選「**剛好滿足**業務要求」的方案，不是越小越好。

### 對應的 DR 策略

| 策略 | 典型 RPO | 典型 RTO | 平時成本 | 作法 |
|---|---|---|---|---|
| Backup & Restore | 小時（看備份頻率） | 數小時 | 最低 | AWS Backup、快照跨 Region 複製；災難時用 CloudFormation 重建 |
| Pilot Light | 秒到分鐘 | 數十分鐘 | 低 | 資料持續複寫（例如 Aurora Global Database），運算資源平時關閉或最小化 |
| Warm Standby | 秒到分鐘 | 分鐘 | 中 | 縮小規模的完整環境持續運作，災難時擴展 |
| Multi-site Active/Active | 接近 0 | 接近 0 | 最高 | 多 Region 同時服務（DynamoDB global tables、Route 53） |

### AWS 服務與 RPO/RTO 的對照

| 服務／功能 | RPO | RTO | 備註 |
|---|---|---|---|
| RDS Multi-AZ | ≈ 0（同步複寫） | 約 1–2 分鐘 | 同 Region 內的高可用 |
| RDS Multi-AZ DB cluster | ≈ 0 | 通常低於 35 秒 | |
| RDS 自動備份＋PITR | 約 5 分鐘 | 還原需數十分鐘以上 | 最長保留 35 天 |
| RDS 跨 Region read replica | 秒級（非同步） | 分鐘級，需手動 promote | |
| Aurora Global Database | 通常低於 1 秒 | 約 1 分鐘內 | 跨 Region DR 首選 |
| DynamoDB PITR | 秒級 | 還原需要時間 | 35 天內任一秒 |
| DynamoDB global tables | 秒級 | 接近 0 | 多 Region 多主 |
| S3 CRR | 通常數分鐘（RTC 保證 15 分鐘） | 接近 0 | |
| AWS Backup 跨 Region 複製 | 取決於排程 | 小時級 | |
| Elastic Disaster Recovery | 秒級（區塊層級持續複寫） | 分鐘級 | 地端或 EC2 的 DR |

### 考試判斷方式

1. **先看題目給的 RPO/RTO，排除做不到的選項**：RPO 小於 1 秒就排除快照與每日備份（Q281）；RPO 15 分鐘、RTO 1 小時，DynamoDB PITR 就夠（Q71）。
2. **再挑最便宜、剛好滿足的方案**：RPO/RTO 都是 24 小時，每天複製快照到另一個 Region 即可（Q588）；「可接受 30 分鐘停機、平時不需服務流量」→ pilot light 或 warm standby，不需要 active-active（Q217、Q955）。
3. **注意關鍵字**：
   - 「minimal data loss」「every transaction on two nodes」→ 同步複寫，例如 RDS Multi-AZ（Q182）。
   - 「lowest RTO」「minimal downtime across Regions」→ Aurora Global Database＋warm standby（Q273）。
   - 「RPO 5 分鐘、RTO 20 分鐘、跨 Region、改動最少」→ Aurora Global Database＋managed failover（Q896）。

**相關題號**：Q71、Q182、Q217、Q273、Q274、Q281、Q434、Q539、Q588、Q874、Q896、Q955

---

## 5. Elastic Load Balancing（ALB、NLB、GWLB、CLB）

### 一句話定位

Elastic Load Balancing（ELB）是託管的負載平衡服務，負責把流量分散到多個 AZ 的 target，並透過健康檢查只把流量送給健康的 target。四種類型的差別在於**工作在哪一層、看得懂多少流量內容**。

| 類型 | OSI 層 | 看得懂什麼 | 一句話 |
|---|---|---|---|
| **ALB**（Application Load Balancer） | L7 | HTTP/HTTPS 的路徑、主機名稱、header、query string | Web 與微服務的智慧路由 |
| **NLB**（Network Load Balancer） | L4 | TCP/UDP/TLS 的 IP 與 port | 極高效能、低延遲、固定 IP |
| **GWLB**（Gateway Load Balancer） | L3 | IP 封包（以 GENEVE 封裝） | 把流量透明地送進第三方防火牆或檢測設備 |
| **CLB**（Classic Load Balancer） | L4／L7 | 基本 HTTP 與 TCP | 舊一代，新架構不使用 |

### ALB（L7）

| 項目 | 內容 |
|---|---|
| 協定 | HTTP、HTTPS、HTTP/2、gRPC、WebSocket |
| 路由規則 | 依 path（`/api/*`）、host（`api.example.com`）、header、method、query string、來源 IP 轉送到不同 target group |
| Target 類型 | EC2 instance、IP（含地端，經 DX/VPN）、**Lambda**、ECS task、EKS pod |
| 內建動作 | HTTP 轉 HTTPS 的 **redirect**、固定回應（fixed response）、**Cognito／OIDC 使用者驗證** |
| TLS | 搭配 ACM 憑證做 **SSL offloading**；用 **SNI** 在同一個 listener 掛多張憑證 |
| 安全 | 可掛 **AWS WAF**（SQL injection、XSS、geo match、rate-based、IP set）；有 security group |
| Session | Sticky session（cookie） |
| 用戶端 IP | 後端看到的是 ALB 的 IP，原始 IP 放在 `X-Forwarded-For` header |
| IP 位址 | **沒有固定 IP**，只能用 DNS 名稱存取 |

**使用情境**

- 一般 Web 應用與 REST API，前面通常再加 CloudFront。
- 微服務與容器：依路徑或主機名稱把請求導到不同服務（ECS、EKS 的 Ingress）。
- 需要 WAF 防護、HTTP 轉 HTTPS、統一登入驗證時。
- Serverless：ALB 直接呼叫 Lambda。

### NLB（L4）

| 項目 | 內容 |
|---|---|
| 協定 | TCP、UDP、TCP_UDP、TLS |
| 效能 | 每秒可處理數百萬個請求，延遲極低，可應付突發流量 |
| 固定 IP | 每個 AZ 一個**固定 IP**，也可以綁 **Elastic IP**，方便用戶端防火牆設白名單 |
| Target 類型 | EC2 instance、IP（含地端）、**ALB**（讓 ALB 也能有固定 IP） |
| 用戶端 IP | 保留原始來源 IP（client IP preservation） |
| TLS | 可以在 NLB 終結 TLS（掛 ACM 憑證），也可以直接 TCP 透傳到後端 |
| 安全 | 新建的 NLB 可以掛 security group（建立時就要設定）；**不支援 WAF** |
| PrivateLink | **VPC endpoint service 必須以 NLB（或 GWLB）為前端**，是跨帳號、跨 VPC 私有提供服務的標準作法 |

**使用情境**

- **UDP** 服務：遊戲、VoIP、IoT、DNS、串流。ALB 不支援 UDP。
- 非 HTTP 的 TCP 服務、非標準 port、極高吞吐量。
- 用戶端只能連白名單中的**固定 IP**。
- 透過 **PrivateLink** 把服務私有地提供給其他 VPC 或其他帳號。
- 搭配 Global Accelerator，提供全球 TCP/UDP 的低延遲入口。

### GWLB（L3）

| 項目 | 內容 |
|---|---|
| 用途 | 把流量導向第三方虛擬設備（防火牆、IDS/IPS、深度封包檢測），並在設備之間分散負載 |
| 運作方式 | 以 **GENEVE 協定（UDP 6081）** 封裝原始封包送到設備，設備檢查後送回，對來源與目的端透明 |
| 搭配元件 | **Gateway Load Balancer Endpoint（GWLBE）**，放在要保護的 VPC，路由表把流量指向它 |
| 架構 | 常見做法是集中式的 inspection VPC 或安全帳號，多個應用 VPC／帳號共用一組設備 |

**使用情境**

- 所有進出流量都要先經過 Palo Alto、Fortinet 等**第三方防火牆**。
- 集中在網路或安全帳號做檢測，同時讓設備可以水平擴展、高可用。

### CLB（舊一代）

同時支援基本的 L4 與 L7，但沒有路徑路由、Lambda target、WAF 等功能。新架構一律選 ALB 或 NLB，考題中 CLB 通常是要被替換的對象。

### 共通功能

| 功能 | 說明 |
|---|---|
| 健康檢查 | ALB 用 HTTP/HTTPS 檢查特定路徑與狀態碼；NLB 可用 TCP、HTTP、HTTPS。只有 HTTP 健康檢查才偵測得到應用層錯誤（Q70） |
| 搭配 Auto Scaling | ASG 掛 target group 後，新 instance 自動註冊；ASG 健康檢查改用 **ELB 類型**，不健康的 instance 才會被替換 |
| 跨 AZ 負載平衡 | ALB 預設開啟；NLB、GWLB 預設關閉，開啟後跨 AZ 傳輸要計費 |
| Deregistration delay | 舊稱 connection draining，移除 target 時先讓進行中的請求完成 |
| Security group 串接 | 後端 EC2 的 SG 只允許「來源為 LB 的 SG」，就能擋掉其他直接連線（Q282） |
| Internet-facing 與 internal | 對外的 LB 放 public subnet，後端 EC2 可放在 private subnet（Q697） |

### 怎麼選

| 題目線索 | 選擇 |
|---|---|
| HTTP/HTTPS、依 path 或 host 路由、微服務、容器 | ALB |
| 需要 WAF、HTTP 轉 HTTPS、Cognito 登入、Lambda target | ALB |
| UDP、非 HTTP 的 TCP、每秒數百萬請求、超低延遲 | NLB |
| 固定 IP、Elastic IP、用戶端防火牆白名單 | NLB（或 Global Accelerator） |
| PrivateLink、跨帳號私有提供服務 | NLB |
| 第三方防火牆、IDS/IPS、流量透明檢測 | GWLB |
| 全球使用者、TCP/UDP、anycast 靜態 IP、快速跨 Region 容錯 | Global Accelerator（後端接 NLB 或 ALB） |
| 全球使用者、HTTP 內容快取 | CloudFront（origin 為 ALB 或 S3） |

### 容易混淆的地方

- **WAF 不能掛在 NLB 上**：WAF 只能掛在 ALB、CloudFront、API Gateway、AppSync、Cognito user pool 等。NLB 遇到 Web 攻擊要在前面加 API Gateway 或 CloudFront 再掛 WAF（Q180）。
- **ALB 沒有固定 IP**：要固定 IP，可以在 ALB 前面放 NLB（ALB-type target）或 Global Accelerator。
- **Route 53 不是負載平衡器**：Route 53 回傳的 IP 可能已經不健康而且有 DNS 快取；要確實只送到健康的 instance，應在前面放 ALB（Q264）。
- **Global Accelerator 和 NLB 不是二選一**：Global Accelerator 是全球入口，負責導到最近、健康的 Region；Region 內仍由 NLB 或 ALB 分散流量（Q461、Q700）。
- **SSL offloading 用 ALB 加 ACM**：讓 EC2 不必處理加解密（Q123）。注意外部 CA 簽發後匯入 ACM 的憑證不會自動續約（Q62）。

### 考試判斷重點

1. 先看**協定**：有 UDP 就排除 ALB，選 NLB。
2. 再看**需求**：路由規則、WAF、驗證選 ALB；固定 IP、PrivateLink、極高吞吐量選 NLB；第三方設備檢測選 GWLB。
3. 高可用題型的標準答案通常是「**ELB＋跨多個 AZ 的 ASG**」，而且 ASG 要使用 ELB 健康檢查。

**相關題號**
- ALB：Q12、Q60、Q62、Q70、Q112、Q123、Q141、Q170、Q213、Q264、Q282、Q340、Q437、Q591、Q608、Q697
- NLB：Q367、Q378、Q382、Q600、Q642、Q704、Q744、Q810、Q876、Q928、Q987
- NLB 搭配 Global Accelerator：Q461、Q700、Q905
- GWLB：Q19、Q945

---

## 6. AWS Network Firewall

### 一句話定位

部署在 VPC 裡的**託管式網路防火牆＋入侵防禦（IPS）**。它檢查所有經過的 VPC 流量（L3–L7），依規則放行、丟棄或告警，不用自己架設與維護防火牆主機。

### 核心特性

| 項目 | 內容 |
|---|---|
| 部署位置 | 在每個 AZ 建一個專用的 **firewall subnet**，裡面放 firewall endpoint；透過**修改路由表**把流量導進 endpoint 檢查 |
| 無狀態規則（stateless） | 依 5-tuple（來源／目的 IP、port、協定）逐封包判斷，可以放行、丟棄或轉給有狀態引擎 |
| 有狀態規則（stateful） | 追蹤連線狀態，支援 **Suricata 相容的 IPS 規則**，可用特徵比對偵測已知攻擊 |
| 網域過濾 | **domain list** 規則依 HTTP Host header 或 TLS SNI 比對網域，可做出站白名單或黑名單 |
| TLS 檢查 | 可以解密 TLS 流量後檢查內容，再重新加密（需搭配 ACM 憑證） |
| 受管規則 | AWS 提供已知惡意網域、威脅特徵等受管規則群組 |
| 記錄 | alert log、flow log、TLS log，可送到 S3、CloudWatch Logs、Kinesis Data Firehose |
| 擴展與可用性 | 自動擴展；每個 AZ 一個 endpoint，所以 endpoint 要跟著 AZ 部署 |
| 多帳號管理 | 用 **AWS Firewall Manager** 統一把防火牆政策套用到 Organizations 中的所有帳號 |
| 計費 | 依 endpoint 小時數＋處理的流量（GB）計費 |

### 常見部署架構

| 架構 | 說明 |
|---|---|
| **分散式** | 每個 VPC 各自部署 Network Firewall，檢查該 VPC 進出網際網路的流量 |
| **集中式（inspection VPC）** | 建一個專用的檢查 VPC，多個 VPC 透過 **Transit Gateway** 把流量繞進去檢查。TGW attachment 要開 **appliance mode**，確保同一條連線的去回程走同一個 AZ |
| **入站檢查** | 在 IGW 的路由表（edge association／ingress routing）把進入 public subnet 的流量先導到 firewall endpoint |
| **出站檢查** | private subnet → firewall endpoint → NAT gateway → IGW，在出口前做網域與威脅過濾 |
| **East-West 檢查** | VPC 之間、VPC 與地端（經 DX／VPN）之間的流量經 TGW 導入檢查 |

### 使用情境

- **出站網域白名單**：private subnet 的 EC2 只能連到核准的軟體儲存庫或 SaaS 網址，其他網際網路流量一律封鎖（Q327）。
- **取代地端防火牆或 IPS 設備**：把地端的流量檢測與過濾功能搬到 VPC，又不想自己管理設備（Q15）。
- **法規或稽核要求**：金融業要求所有進出流量都要經過防火牆檢查並留下紀錄。
- **集中式網路安全**：在網路帳號建一個 inspection VPC，統一檢查所有應用 VPC 的南北向與東西向流量。
- **阻擋已知惡意目的地**：套用受管威脅情資規則，阻擋連往惡意網域或 C&C 伺服器的連線。

### 和其他安全服務的比較

| 服務 | 層級 | 作用範圍 | 用途 |
|---|---|---|---|
| Security Group | L4，有狀態 | ENI／instance | 只能寫放行規則，管某台機器能接受哪些連線 |
| Network ACL | L4，無狀態 | Subnet | 可以寫放行與拒絕規則，例如封鎖特定 IP |
| **Network Firewall** | L3–L7，有狀態＋無狀態 | VPC 流量（經路由導入） | 網域過濾、IPS、深度封包檢測、集中管控 |
| AWS WAF | L7 HTTP | ALB、CloudFront、API Gateway 等 | SQL injection、XSS、bot、rate limit 等 Web 攻擊 |
| Route 53 Resolver DNS Firewall | DNS 查詢 | VPC 的 DNS 解析 | 阻擋解析惡意網域，但繞過 DNS 直接連 IP 時無效 |
| Shield | L3／L4（Advanced 含 L7） | 對外資源 | DDoS 防護 |
| GWLB＋第三方設備 | L3 | VPC 流量 | 想沿用 Palo Alto、Fortinet 等既有廠牌設備時 |

### 容易混淆的地方

- **Network Firewall 和 WAF 不能互相取代**：Web 應用的 SQL injection、XSS 防護選 WAF（Q732）；VPC 層級的流量過濾、IPS、出站網域控管選 Network Firewall。
- **Network Firewall 和 GWLB 的差別**：兩者都能做集中式檢查。要 AWS 託管、不想管設備就用 Network Firewall；指定要用第三方廠牌的虛擬防火牆就用 GWLB（Q19、Q945）。Network Firewall 底層其實也使用 GWLB 技術。
- **一定要改路由表**：只建立防火牆不會有任何效果，流量必須透過路由表導進 firewall endpoint。
- **SG 和 NACL 做不到網域過濾**：它們只認 IP、port 與協定；要依網域名稱放行出站流量，就要用 Network Firewall 或 proxy。
- **DNS Firewall 和 Network Firewall 是互補的**：DNS Firewall 只管 DNS 查詢；Network Firewall 檢查實際的連線流量。

### 考試判斷重點

- 「inspect / filter traffic」「IPS／IDS」「only allow outbound to approved domains／URLs」「centralized inspection」，而且「AWS managed」「最少維運」→ **AWS Network Firewall**。
- 「third-party firewall appliances」→ **GWLB**。
- 「SQL injection、XSS、Web 攻擊」→ **WAF**。
- 「多帳號統一防火牆政策」→ **Firewall Manager**（可以管理 Network Firewall、WAF、Shield Advanced、Security Group 政策）。

**相關題號**
- 選 Network Firewall：Q15、Q327
- 改選其他服務：Q732（WAF）、Q19、Q945（GWLB＋第三方設備）

---

## 7. Amazon Cognito（User Pool 與 Identity Pool）

### 一句話定位

給**自家應用的終端使用者**（客戶、會員、App 使用者）用的身分服務。它有兩個元件，分別解決兩個不同的問題：

| 元件 | 解決的問題 | 產出 |
|---|---|---|
| **User Pool** | **你是誰？**（驗證，Authentication）：註冊、登入、MFA、社群登入 | **JWT token**（ID token、access token、refresh token） |
| **Identity Pool** | **你能存取哪些 AWS 資源？**（授權，Authorization）：把使用者對應到 IAM role | **臨時 AWS 憑證**（經 STS 發行） |

> 記法：User Pool 管「**登入**」，Identity Pool 管「**拿 AWS 憑證**」。

### User Pool

| 功能 | 說明 |
|---|---|
| 使用者目錄 | 託管的使用者資料庫，處理註冊、登入、密碼重設、email／簡訊驗證，可擴展到數百萬使用者 |
| 託管登入頁面 | Hosted UI（managed login）提供現成的登入與註冊頁面，可以自訂網域與外觀 |
| 聯合登入 | 支援 Google、Facebook、Apple、Amazon 等社群登入，以及企業的 **SAML** 與 **OIDC** IdP |
| MFA | 簡訊、TOTP 驗證器 App、email 等 |
| 進階安全（threat protection） | **風險式 adaptive authentication**：偵測異常地點、IP、裝置時要求額外驗證或封鎖；也能偵測外洩的密碼（Q803） |
| Lambda triggers | 在註冊前後、驗證前後、產生 token 前等時機執行自訂邏輯，例如自動確認帳號、加入自訂 claim、從舊系統遷移使用者 |
| Token | 登入成功後發行 JWT：ID token（使用者資訊）、access token（存取 API 用）、refresh token（換新 token） |

**User Pool 能直接整合的服務**

| 服務 | 用法 |
|---|---|
| **API Gateway** | REST API 設定 **Cognito user pool authorizer**，自動驗證 JWT，不用寫程式（Q200、Q792）。HTTP API 則用 JWT authorizer |
| **ALB** | listener rule 加上 **authenticate-cognito** 動作，使用者未登入時先導到登入頁 |
| **AppSync** | GraphQL API 的授權方式之一 |
| **CloudFront＋Lambda@Edge** | 在邊緣驗證 JWT，做低延遲的全球授權（Q345、Q871） |

### Identity Pool

| 功能 | 說明 |
|---|---|
| 換取 AWS 憑證 | 使用者用 User Pool、社群登入、SAML 或 OIDC 的 token 換取**臨時的 AWS 憑證**，直接呼叫 S3、DynamoDB 等服務 |
| 角色對應 | **authenticated role**（已登入使用者）與 **unauthenticated role**（訪客，可選擇開啟）；也可以依 token 的 claim 對應到不同的 IAM role |
| 細緻權限 | IAM policy 可以用變數 `${cognito-identity.amazonaws.com:sub}`，讓每位使用者只能存取 S3 上自己的資料夾或 DynamoDB 中自己的資料 |

**典型流程**

```
使用者 ──登入──► User Pool ──JWT──► Identity Pool ──► STS 臨時憑證（IAM role）
                                                           │
                                                           ▼
                                               直接存取 S3／DynamoDB
```

### 使用情境

- **Web 與行動 App 的會員系統**：註冊、登入、忘記密碼、社群登入，不用自己開發與維護身分系統。
- **保護 API**：API Gateway 或 ALB 搭配 User Pool，只有已登入的使用者能呼叫（Q200、Q792）。
- **App 直接存取 AWS 資源**：行動 App 上傳照片到 S3、讀寫 DynamoDB，不需要把 Access Key 寫在 App 裡（Q325、Q1011）。
- **全球低延遲的內容授權**：CloudFront＋Lambda@Edge 驗證 Cognito 發行的 JWT（Q345、Q871）。
- **Serverless 網站的付費會員登入**：搭配 API Gateway、Lambda、DynamoDB，閒置時幾乎不花錢（Q541）。
- **風險式 MFA**：使用者從陌生地點或裝置登入時才要求第二道驗證（Q803）。

### 容易混淆的地方

- **User Pool 和 Identity Pool 不能互換**：只要「登入驗證」選 User Pool（Q541 中 identity pool 是錯誤選項）；要「拿 AWS 臨時憑證存取 S3／DynamoDB」選 Identity Pool（Q1011 中 user pool 是錯誤選項，因為它只發 JWT）。
- **Cognito 和 IAM Identity Center 的對象不同**：Cognito 給**應用的終端使用者**；IAM Identity Center（舊稱 AWS SSO）給**員工**登入 AWS 主控台與多個 AWS 帳號。
- **Cognito 和 Directory Service 不同**：Directory Service 提供 Microsoft AD，給需要 AD 的企業工作負載使用，成本較高，也不是 serverless（Q345）。
- **權限錯誤要看 IAM role**：使用者已登入卻無法存取 S3，通常是 identity pool 對應的 IAM role 權限不足，要修改 role 的 policy（Q325）。
- **private subnet 存取 S3 還要考慮網路路徑**：拿到 Identity Pool 憑證後，private subnet 的應用要透過 S3 VPC endpoint 存取 S3，而不是走 NAT gateway（Q1011）。
- **費用以月活躍使用者（MAU）計算**：AWS 在 2024 年底調整了 Cognito 的方案與免費額度，考題中「50,000 MAU 免費」是舊的價格。實際費用以官方價目表為準，考試上只要記得「使用者少時非常便宜」即可。

### 考試判斷重點

- 「sign-up / sign-in」「user directory」「social login」「millions of users」「serverless authentication」→ **Cognito User Pool**。
- 「API Gateway 驗證使用者、最少開發」→ **Cognito user pool authorizer**。
- 「mobile/web app users access S3 or DynamoDB directly」「temporary AWS credentials」→ **Cognito Identity Pool**。
- 「員工登入多個 AWS 帳號」→ **IAM Identity Center**，不是 Cognito。

**相關題號**
- 選 Cognito：Q200、Q325、Q345、Q541、Q792、Q803、Q871、Q1011
- 出現在選項中可對照：Q319、Q366、Q390、Q457、Q484、Q503、Q624、Q922、Q1018

---

## 8. RDS Performance Insights

### 一句話定位

RDS 與 Aurora 的**資料庫效能分析儀表板**。它回答：「**資料庫現在忙不忙？忙在哪裡？是哪幾條 SQL 造成的？**」

> **服務現況（2026 年）**：AWS 正把 Performance Insights 的功能移到 **CloudWatch Database Insights**。第三方資料指出，原本的終止日期 2025-11-30 已延後到 2026-06-30；但這個日期，以及終止範圍究竟是主控台、付費保留方案還是 API，我都沒能用 AWS 官方文件確認。依同一份資料，取代方案分兩種：
> - **Database Insights Standard**：免費，保留 7 天。
> - **Database Insights Advanced**：付費，保留 15 個月，另外提供 fleet 層級監控、執行計畫分析、鎖定分析等功能。
>
> 考題仍以「Performance Insights」為名，下面的核心概念在 Database Insights 中一樣適用。

### 核心概念

| 概念 | 說明 |
|---|---|
| **DB load（資料庫負載）** | 核心指標，以 **AAS（Average Active Sessions，平均活躍工作階段數）** 表示：某個時間點平均有幾個 session 正在執行或等待 |
| **Max vCPU 線** | 圖上的一條水平線，代表 instance 的 vCPU 數。**DB load 長時間高於這條線**，代表 session 在排隊等 CPU 或其他資源，資料庫已經過載 |
| **Wait events（等待事件）** | 把負載依「在等什麼」拆開：CPU、I/O（讀寫磁碟）、lock（鎖定）、網路、commit 等。看哪一種等待最多，就知道瓶頸在哪裡 |
| **Top SQL** | 列出對負載貢獻最大的 SQL 語句，可以直接找到要優化的查詢 |
| **Dimensions（維度）** | 負載可以依 wait、SQL、host、user、database 等維度切分，找出是哪台應用主機或哪個帳號造成的 |
| **Counter metrics** | 資料庫引擎與 OS 的計數器，例如 buffer hit、連線數、tmp table |
| **保留期間** | 免費保留 7 天；舊的付費方案最長保留 24 個月 |
| **存取方式** | 主控台儀表板、API（例如 `GetResourceMetrics`），`DBLoad` 指標也會送到 CloudWatch，可以設定警報 |
| **支援引擎** | Aurora MySQL／PostgreSQL，以及 RDS for MySQL、MariaDB、PostgreSQL、Oracle、SQL Server（各引擎版本與 instance 類型有限制） |

### 怎麼解讀

```
DB load（AAS）
  ▲
8 │        ████
  │       ██████          ← 主要是 CPU：找 Top SQL，優化查詢或加索引
4 │- - - -██████- - - - - ← Max vCPU（4 vCPU）
  │  ██  ████████  ██
  │ ████████████████████  ← 主要是 IO：考慮加大 IOPS、加快取或讀取副本
  └──────────────────────────────► 時間
```

| 觀察結果 | 可能原因 | 常見改善方向 |
|---|---|---|
| 負載以 CPU 為主，而且超過 Max vCPU | 查詢計算量大、缺少索引 | 優化 Top SQL、加索引、scale up |
| 負載以 I/O 等待為主 | 大量磁碟讀寫 | 提高 IOPS（gp3、io2）、加 ElastiCache、讀取流量導向 read replica |
| 負載以 lock 等待為主 | 交易互相阻擋 | 調整交易設計、縮短交易時間 |
| 某個 host 或 user 的負載特別高 | 某支應用或批次作業造成 | 錯開批次時間、限制該應用的連線 |

### 和其他監控工具的比較

| 工具 | 看什麼 | 粒度 | 回答的問題 |
|---|---|---|---|
| **CloudWatch 基本指標** | CPUUtilization、FreeableMemory、ReadIOPS、DatabaseConnections | 1 分鐘，hypervisor 層級 | 資源用量高不高 |
| **Enhanced Monitoring** | OS 層級：每個 process 的 CPU、記憶體、檔案系統 | 最細 1 秒，由 instance 上的 agent 收集，送到 CloudWatch Logs | OS 裡是哪個 process 在吃資源 |
| **Performance Insights** | 資料庫引擎層級：DB load、等待事件、Top SQL | 秒級取樣 | 資料庫忙在哪裡、是哪條 SQL |
| **DevOps Guru for RDS** | 以 ML 偵測效能異常，並提出原因與建議 | — | 有沒有異常、可能的根因是什麼 |
| **慢查詢日誌／error log** | 執行時間超過門檻的 SQL、錯誤訊息 | 依日誌 | 哪些 SQL 特別慢 |

### 使用情境

- **效能問題排查**：應用變慢時，先看 DB load 是否超過 Max vCPU，再依等待事件與 Top SQL 找到瓶頸。
- **容量規劃**：觀察長期的負載趨勢，判斷要 scale up、加 read replica，還是導入快取。
- **SQL 優化**：開發或 DBA 團隊依 Top SQL 排出優化的優先順序。
- **設定警報**：對 CloudWatch 的 `DBLoad` 指標設定警報，負載持續超過 vCPU 數時通知。

### 容易混淆的地方

- **它是觀察工具，不能修復問題**：Performance Insights 只告訴你瓶頸在哪裡，不會自動調整。改善要靠 read replica、ElastiCache、RDS Proxy、加大 instance 或優化 SQL。
- **Failover 太久不是靠它解決**：Multi-AZ failover 時應用逾時，答案是 **RDS Proxy**，由 proxy 保持連線並導向新的主庫；開 Performance Insights 監控 CPU 是錯誤選項（Q958）。
- **和 Enhanced Monitoring 的分工**：要看 OS 層級的 process 用量選 Enhanced Monitoring；要看 SQL 與等待事件選 Performance Insights。
- **考試出現頻率低**：在這份題庫中，它只出現在題目背景（Q30）與錯誤選項（Q958），沒有一題以它為正確答案。知道它的用途、能和其他監控工具區分即可。

### 考試判斷重點

- 「identify which SQL queries cause high load」「analyze database performance」「wait events」→ **Performance Insights**。
- 「OS-level metrics」「process-level」「granularity of 1 second」→ **Enhanced Monitoring**。
- 「detect anomalies automatically with ML、recommendations」→ **DevOps Guru for RDS**。
- 要「解決」連線過多、failover 太慢、讀取負載過重 → RDS Proxy、Multi-AZ、read replica、ElastiCache，而不是監控工具。

**相關題號**：Q30（題目背景）、Q958（錯誤選項，正確答案為 RDS Proxy）

---

## 9. 資源標籤治理與 AWS Config required-tags

### 從 Q31 說起

> **Q31**：公司要確保所有 EC2 instance、RDS DB instance、Redshift cluster 都有設定標籤，並希望**設定與維運這項檢查的工作量最少**。
>
> - **A. 用 AWS Config 規則定義並偵測沒有正確加標籤的資源。** ✅
> - B. 用 Cost Explorer 顯示沒有正確加標籤的資源，再手動補上。
> - C. 自己寫 API 呼叫檢查所有資源，定期在 EC2 上執行。
> - D. 自己寫 API 呼叫檢查所有資源，用 CloudWatch 排程 Lambda 定期執行。

**為什麼選 A**：AWS Config 有現成的受管規則 **`required-tags`**，只要填入要檢查的標籤鍵（與允許的值），就會在資源建立或變更時自動評估，不用寫也不用維護程式。

- **B 錯**：Cost Explorer 是成本分析工具，不做合規偵測，而且手動補標籤不符合「最少維運」。
- **C、D 錯**：要自己寫程式、維護排程與執行環境，工作量最大。

### 標籤（Tag）是什麼、用來做什麼

標籤是附加在 AWS 資源上的 **key＝value** 中繼資料，例如 `CostCenter=FIN`、`Environment=prod`、`Owner=team-a`。

| 用途 | 說明 | 相關題號 |
|---|---|---|
| 成本分攤 | 在 Billing 啟用為**成本分配標籤**後，可以在 Cost Explorer 與帳單中依標籤分組 | Q459、Q559 |
| 資源搜尋與分組 | **Resource Groups 與 Tag Editor** 可以跨 Region、跨服務依標籤找資源，也能批次加標籤 | Q211 |
| 自動化範圍 | AWS Backup 備份計畫、SSM Patch Manager、Lambda 排程啟停等都能依標籤選取資源 | Q512 |
| 存取控制（ABAC） | IAM policy 用 `aws:ResourceTag`、`aws:RequestTag`、`aws:PrincipalTag` 依標籤決定權限 | |
| 合規與治理 | 用 Config 偵測缺少標籤的資源，用 Tag Policies 或 SCP 統一規範 | Q31、Q433 |

### 還有哪些服務有標籤？

**幾乎所有 AWS 服務都支援標籤**，包括 S3、Lambda、DynamoDB、ECS、EKS、SNS、SQS、KMS、ELB、VPC 相關資源、CloudFormation stack 等。可以用 **Resource Groups Tagging API**（`GetResources`、`TagResources`）跨服務統一查詢或加標籤。少數資源或子資源不支援標籤，或只能在建立時加，要以各服務文件為準。

但要注意：**「服務支援標籤」和「`required-tags` 規則能檢查」是兩回事**。`required-tags` 只支援以下資源類型（依 AWS 文件，共 30 種）：

| 服務 | 支援的資源類型 |
|---|---|
| EC2／VPC | Instance、Volume、SecurityGroup、NetworkInterface、VPC、Subnet、RouteTable、NetworkAcl、InternetGateway、CustomerGateway、VPNConnection、VPNGateway |
| RDS | DBInstance、DBSnapshot、DBSubnetGroup、DBSecurityGroup、EventSubscription |
| Redshift | Cluster、ClusterSnapshot、ClusterSubnetGroup、ClusterParameterGroup、ClusterSecurityGroup |
| 負載平衡 | Classic Load Balancer（`ElasticLoadBalancing::LoadBalancer`）、ALB/NLB（`ElasticLoadBalancingV2::LoadBalancer`） |
| 其他 | S3 Bucket、DynamoDB Table、Auto Scaling Group、CloudFormation Stack、CodeBuild Project、ACM Certificate |

清單中**沒有** Lambda、ECS、EKS、SNS、SQS、KMS 等。這些資源要檢查標籤，可以：

- 自己寫 **自訂 Config 規則**（Lambda 或 Guard）。
- 用 **Tag Policies** 的強制功能，在加標籤時就擋下不合規的值。
- 用 Resource Groups Tagging API 定期查詢沒有標籤的資源。

### 如何用 AWS Config 設定 required-tags

**前置條件**：該 Region 已啟用 AWS Config 的 **configuration recorder**，並記錄要檢查的資源類型。另外，Config 並非對所有資源類型都會記錄標籤，要確認目標資源類型有被記錄。

**規則規格**

| 項目 | 內容 |
|---|---|
| 規則識別碼 | `REQUIRED_TAGS` |
| 觸發方式 | 組態變更觸發（資源建立或修改時評估） |
| 參數 | `tag1Key`（必填）、`tag1Value`（選填）……最多到 `tag6Key`／`tag6Value`，**一條規則最多檢查 6 個標籤** |
| 值的格式 | `tagNValue` 可以填多個允許值，以逗號分隔，例如 `FIN,HR,IT`；不填代表只要有這個 key 即可 |
| 範圍 | 可以指定資源類型，只檢查 EC2、RDS、Redshift |

**方法一：主控台**

1. 開啟 AWS Config 主控台 → **Rules** → **Add rule**。
2. 選 **Add AWS managed rule**，搜尋並選擇 **required-tags**。
3. **Scope of changes** 選 **Resources**，資源類型加入 `AWS::EC2::Instance`、`AWS::RDS::DBInstance`、`AWS::Redshift::Cluster`。
4. **Parameters** 填入 `tag1Key = CostCenter`（需要的話再填 `tag1Value = FIN,HR,IT`、`tag2Key = Owner` 等）。
5. 儲存後，規則會評估現有資源，之後每次資源變更都會重新評估。

**方法二：AWS CLI**

```bash
aws configservice put-config-rule --config-rule '{
  "ConfigRuleName": "required-tags-ec2-rds-redshift",
  "Source": { "Owner": "AWS", "SourceIdentifier": "REQUIRED_TAGS" },
  "InputParameters": "{\"tag1Key\":\"CostCenter\",\"tag1Value\":\"FIN,HR,IT\",\"tag2Key\":\"Owner\"}",
  "Scope": {
    "ComplianceResourceTypes": [
      "AWS::EC2::Instance",
      "AWS::RDS::DBInstance",
      "AWS::Redshift::Cluster"
    ]
  }
}'

# 列出不合規的資源
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name required-tags-ec2-rds-redshift \
  --compliance-types NON_COMPLIANT
```

**方法三：多帳號部署**

- 從管理帳號或委派管理員帳號用 `put-organization-config-rule`，一次部署到組織內所有帳號。
- 或把規則放進 **Conformance Pack**，和其他規則一起部署。
- 用 **Aggregator** 集中檢視各帳號、各 Region 的結果。

**通知與修復**

| 動作 | 作法 |
|---|---|
| 通知 | 建立 EventBridge 規則，事件來源 `aws.config`、detail-type 為 `Config Rules Compliance Change`，目標設為 SNS |
| 修復 | AWS 文件註明，AWS 受管的 SSM 文件 **`AWS-SetRequiredTags` 不能作為這條規則的修復動作**，要自己建立 SSM Automation 文件，或用 Lambda 呼叫 Resource Groups Tagging API 補標籤（Q512 的「以程式自動加上標籤」就是這個做法） |

> **補充更正**：《詳解》Q31 的解析寫到「可搭配自動修復」。這句話成立的前提是使用自訂的修復文件；AWS 受管的 `AWS-SetRequiredTags` 不適用於 `required-tags`。

### Cost Explorer 和 AWS Config 的關係

兩者是**不同的服務，Cost Explorer 不屬於 AWS Config**。

| | AWS Config | Cost Explorer |
|---|---|---|
| 所屬 | 管理與治理（Management & Governance） | **AWS Billing and Cost Management**（帳務與成本管理） |
| 看什麼 | 資源的**設定**與合規狀態 | **花了多少錢**、花在哪裡、未來趨勢 |
| 能否偵測缺少標籤的資源 | 可以（`required-tags`） | 不行，只能依「已啟用的成本分配標籤」分組成本；沒有標籤的費用只會歸在「No tag」 |
| 同一家族的其他工具 | Conformance Packs、Aggregator | AWS Budgets、Cost Anomaly Detection、Cost and Usage Report（CUR）、Savings Plans／RI 建議 |

兩者唯一的交集是**標籤**：Config 確保資源有加標籤；在 Billing 主控台把標籤啟用為成本分配標籤後，Cost Explorer 才能依標籤分析成本。

### 偵測之外：預防與自動加標籤

`required-tags` 只能**事後偵測**，不能阻止沒有標籤的資源被建立。要預防或自動化，可以搭配：

| 方法 | 作用 | 相關題號 |
|---|---|---|
| **Tag Policies**（Organizations） | 統一標籤 key 的大小寫與允許值；開啟強制（enforced_for）後，可以擋下不合規的標籤操作。但它**不能強制資源一定要有標籤** | |
| **SCP／IAM policy** | 用 `aws:RequestTag` 條件拒絕「建立時沒帶指定標籤」的請求；用 `aws:TagKeys` 拒絕修改或刪除特定標籤 | Q433 |
| **CloudFormation／IaC** | 在 stack 層級設定標籤，自動套用到 stack 建立的資源 | |
| **EventBridge＋Lambda** | 收到 CloudTrail 的建立資源事件後，由 Lambda 自動加標籤（例如建立者、成本中心） | Q653 |
| **成本分配標籤** | 標籤要在管理帳號的 Billing 主控台**啟用**為成本分配標籤，才會出現在 Cost Explorer 與帳單中 | Q459、Q559 |

### 考試判斷重點

- 「偵測沒加標籤的資源」「最少維運」→ **AWS Config `required-tags`**（Q31）。
- 「防止標籤被修改或刪除」「多帳號」→ **SCP**（Q433）。Config 只能偵測，不能預防。
- 「跨 Region、跨服務找出有某標籤的資源」→ **Resource Groups Tag Editor**（Q211）。
- 「依標籤看成本」→ 在管理帳號**啟用成本分配標籤**，再用 Cost Explorer 分組（Q459、Q559）。
- 「建立資源時自動加標籤」→ **EventBridge＋Lambda**（Q653）。

**相關題號**：Q31、Q211、Q433、Q459、Q512、Q559、Q653

---

## 10. Kinesis、DynamoDB、Lambda 的關係與使用情境

### 一句話定位

這三個服務常被組成一條 **serverless 的即時資料管線**，各自扮演不同角色：

| 服務 | 角色 | 比喻 |
|---|---|---|
| **Kinesis Data Streams** | **接收與緩衝**大量、連續的即時資料 | 輸送帶 |
| **Lambda** | **處理**：讀取資料、轉換、過濾、計算 | 輸送帶旁的工人 |
| **DynamoDB** | **儲存**處理結果，提供毫秒級讀寫 | 倉庫 |

```
裝置／App／網站 ──► Kinesis Data Streams ──► Lambda ──► DynamoDB
   （產生資料）         （接收、緩衝、排序）     （處理）    （儲存、查詢）
```

反過來，**DynamoDB 也可以是資料的起點**：資料表的變更經 DynamoDB Streams 觸發 Lambda，做通知、同步或彙總。

### Kinesis 家族

| 服務 | 用途 | 延遲 | 重點 |
|---|---|---|---|
| **Kinesis Data Streams（KDS）** | 即時串流的接收與緩衝，可以有多個消費者 | 即時（約 1 秒內，視消費方式而定） | 以 **shard** 為容量單位；同一 partition key 進同一個 shard，**shard 內保證順序**；資料保留 **24 小時（預設）到 365 天**，可以重複讀取（replay） |
| **Amazon Data Firehose**（原 Kinesis Data Firehose） | 把串流資料**投遞到目的地**：S3、Redshift、OpenSearch、Splunk 等 | 近即時（會先緩衝） | 全託管、自動擴展、不用管 shard；可用 Lambda 轉換、轉成 Parquet；**不能 replay，也沒有多消費者** |
| **Managed Service for Apache Flink**（原 Kinesis Data Analytics） | 對串流做 SQL 或 Flink 即時分析 | 即時 | 視窗彙總、異常偵測 |
| **Kinesis Video Streams** | 影像串流 | — | 攝影機、影像分析 |

**KDS 容量**

| 模式 | 說明 |
|---|---|
| Provisioned | 自己決定 shard 數。每個 shard 寫入 1 MB/s 或 1,000 筆/s，讀取 2 MB/s |
| **On-demand** | 依流量自動調整容量，適合流量不可預測的情況（Q888） |

### Lambda 如何讀 Kinesis

Lambda 透過 **event source mapping** 主動輪詢（poll）KDS 的每個 shard，把一批記錄交給函數處理。

| 設定 | 說明 |
|---|---|
| Batch size／batching window | 一次處理多少筆，或最多等多久湊成一批 |
| 順序 | 同一個 shard 內依序處理；一批失敗時，預設會重試到成功或資料過期，**後面的記錄會被卡住** |
| 錯誤處理 | 可以設定最大重試次數、記錄最大年齡、**bisect batch on error**（把失敗的批次切半重試），以及 **on-failure destination**（把失敗資訊送到 SQS 或 SNS） |
| Parallelization factor | 每個 shard 最多可以同時有 10 個 Lambda 處理（同一 partition key 仍維持順序） |
| Enhanced fan-out | 每個消費者有專屬的 2 MB/s 讀取頻寬，延遲更低，適合多個消費者 |

### DynamoDB 的兩種變更串流

DynamoDB 每次新增、修改、刪除 item 都可以產生變更紀錄，有兩種選擇：

| | **DynamoDB Streams** | **Kinesis Data Streams for DynamoDB** |
|---|---|---|
| 保留期間 | 24 小時 | 依 KDS 設定，最長 365 天 |
| 消費者 | 建議同時最多 2 個 | 多個（可用 enhanced fan-out） |
| 順序與重複 | 每個 item 的變更依序出現，且只出現一次 | 可能亂序或重複，要用時間戳記處理 |
| 整合 | **Lambda trigger** 最常見；Global Tables 也用它複寫 | 可接 Firehose、Flink 等 Kinesis 生態系 |
| 適合 | 資料表變更後觸發動作 | 長期保留變更、多個分析系統同時消費 |

DynamoDB Streams 可以設定記錄的內容（stream view type）：只有 key、新的 item、舊的 item，或新舊都記錄。

### 三種常見架構

**1. 串流攝取 → 處理 → 儲存**

```
手機遊戲／IoT／交易 ──► KDS ──► Lambda（轉換、去除敏感資料、計算）──► DynamoDB
```

- 多個內部應用都要近即時取得交易資料，並在存入文件資料庫前移除敏感資料（Q33）。
- 遊戲分數更新要承受流量暴增、依接收順序處理，再存進高可用的資料庫供排行榜使用（Q735）。
- 第三方以 REST 送來的資料暴增時 EC2 撐不住，改由 KDS 緩衝、Lambda 處理（Q611）。

**2. 資料表變更 → 觸發動作**

```
DynamoDB ──DynamoDB Streams──► Lambda ──► SNS／另一個資料表／OpenSearch／外部 API
```

- 每新增一筆天氣事件就通知四個團隊，而且不影響現有應用：開 DynamoDB Streams，由 Lambda 發布到 SNS（Q400）。
- 訂單寫入後寄送確認信、更新彙總表、同步到搜尋引擎。

**3. 串流攝取 → 投遞到資料湖**

```
來源 ──► KDS 或直接 Firehose ──(Lambda 轉換)──► S3／Redshift／OpenSearch
```

- 不需要即時處理、只要把資料可靠地存進 S3 分析時，Firehose 最省事（Q40、Q547、Q587）。
- API Gateway → KDS → Firehose（Lambda 轉換）→ S3，全部託管（Q77）。

### 什麼時候不要用這個組合

| 情況 | 改用 |
|---|---|
| 每筆處理超過 **15 分鐘**（Lambda 執行時間上限） | ECS on Fargate、AWS Batch（Q865） |
| 只是工作佇列，每則訊息只要被處理一次、不需要 replay 或多消費者 | **SQS**（要保證順序用 SQS FIFO） |
| 要複雜的關聯查詢、交易跨多張表 | RDS／Aurora，而不是 DynamoDB |
| 只要把串流存到 S3，不需要即時處理 | Firehose 直接投遞，不必經過 KDS＋Lambda |

### 容易混淆的地方

- **KDS 和 Firehose**：KDS 是即時、可 replay、可多消費者，但要自己決定由誰消費；Firehose 是近即時投遞，**不能直接當作 Lambda 的即時事件來源**，也不能 replay。題目說「即時分析」選 KDS（Q888）；說「存到 S3、最少維運」選 Firehose。
- **保留期間**：KDS 預設只保留 24 小時。消費者隔天才讀取，資料就已經過期，要延長保留期（Q402）。
- **順序**：KDS 以 partition key 保證同一 shard 內的順序；SQS FIFO 以 message group ID 保證順序。兩者都是「依 payment ID 保證順序」這類題目的正解（Q362）。
- **KDS 和 SQS**：KDS 的資料被讀取後仍然保留，多個應用可以各自讀取同一份資料；SQS 的訊息被處理後就刪除，一則訊息通常只由一個消費者處理。
- **DynamoDB Streams 和 KDS for DynamoDB**：要「資料表變更後觸發 Lambda」選 DynamoDB Streams；要長期保留變更或接 Kinesis 生態系，選 KDS for DynamoDB。

### 考試判斷重點

- 「real-time」「multiple consumers」「ordering」「replay」→ **Kinesis Data Streams**。
- 「deliver to S3／Redshift／OpenSearch」「near real-time」「least operational overhead」→ **Firehose**。
- 「serverless processing of stream records」→ **Lambda**（每筆要在 15 分鐘內處理完）。
- 「low-latency, highly available, scalable NoSQL storage」→ **DynamoDB**。
- 「react to every new／changed item in DynamoDB」→ **DynamoDB Streams＋Lambda**。

**相關題號**
- KDS＋Lambda＋DynamoDB：Q33、Q735
- DynamoDB Streams＋Lambda：Q400
- KDS＋Lambda：Q611、Q888
- Firehose（可搭配 Lambda 轉換）：Q40、Q77、Q547、Q587
- 順序、保留期間與執行時間限制：Q362、Q402、Q865

---

## 11. Amazon Redshift

### 一句話定位

AWS 的**雲端資料倉儲**（data warehouse），專門用來對大量歷史資料做 **SQL 分析與報表**（OLAP），可以從 GB 擴展到 PB 級。它不是給應用程式日常讀寫交易資料用的資料庫（OLTP）。

| | OLTP（RDS、Aurora、DynamoDB） | OLAP（Redshift） |
|---|---|---|
| 典型操作 | 大量的小交易：新增訂單、查詢單一客戶 | 少量的大查詢：彙總過去三年各區域的銷售 |
| 資料量 | 目前營運所需的資料 | 多年累積的歷史資料，來自多個系統 |
| 儲存方式 | 列式（row-based） | **欄式（columnar）** |
| 使用者 | 應用程式 | 分析師、BI 工具、資料科學家 |

### 為什麼查詢快

| 技術 | 說明 |
|---|---|
| **欄式儲存** | 只讀取查詢用到的欄位，搭配高壓縮率，大幅減少 I/O |
| **MPP（Massively Parallel Processing）** | 把資料分散到多個 compute node；leader node 把查詢拆開後平行執行，再彙整結果 |
| 分配鍵與排序鍵 | 依 distribution key 決定資料放在哪個 node，依 sort key 排序，減少掃描範圍 |
| 結果快取與 materialized view | 重複的查詢直接回傳快取結果；常用的彙總可以預先計算 |

### 部署方式

| 方式 | 說明 | 適合 |
|---|---|---|
| **Provisioned cluster** | 自己選 node 類型與數量。**RA3** node 搭配 Redshift Managed Storage，運算與儲存可以分開擴展 | 負載穩定、可預測，可以買 Reserved Nodes 降低成本 |
| **Redshift Serverless** | 不用管理叢集，依 RPU（Redshift Processing Unit）用量計費，自動擴展 | 負載不固定、間歇使用，或要求 serverless（Q804） |

Provisioned cluster 可以 **pause／resume**，不用時暫停運算費用，也可以排程在特定時段執行分析工作（Q515）。

### 重要功能

| 功能 | 說明 |
|---|---|
| **COPY／UNLOAD** | `COPY` 從 S3、DynamoDB、EMR 平行載入資料，是最常用的大量載入方式；`UNLOAD` 把查詢結果匯出到 S3 |
| **Redshift Spectrum** | 不必載入，**直接用 SQL 查詢 S3 上的資料**，並可以和 Redshift 內的資料表 join，依掃描量計費 |
| **Federated query** | 直接查詢 RDS／Aurora（PostgreSQL、MySQL）中的即時資料 |
| **Zero-ETL integration** | Aurora、RDS、DynamoDB 等來源的資料自動近即時同步到 Redshift，不用自己建 ETL 管線 |
| **Streaming ingestion** | 直接從 Kinesis Data Streams 或 MSK 攝取串流資料 |
| **Data sharing** | 跨叢集、跨帳號、跨 Region 共享資料，不用複製 |
| **Concurrency scaling** | 同時查詢的數量大增時，自動加開暫時性的運算容量 |
| **Redshift ML** | 用 SQL 的 `CREATE MODEL` 建立並訓練模型（背後使用 SageMaker），再以 SQL 做推論（Q804） |
| **Data API** | 不用維護 JDBC 連線，以 HTTPS API 執行 SQL，適合 Lambda 等 serverless 應用 |
| **Workload management（WLM）** | 依查詢類型分配資源與優先順序，避免大查詢拖慢報表 |

### 可用性、備份與安全

| 項目 | 內容 |
|---|---|
| 可用性 | 預設在單一 AZ；RA3 叢集可以開啟 **Multi-AZ** 部署 |
| 備份 | 自動 snapshot 存到 S3（保留 1–35 天），也可以手動 snapshot；可以設定**跨 Region 複製 snapshot** 做 DR |
| 加密 | 靜態加密使用 KMS 或 HSM，傳輸加密使用 SSL，也支援用戶端加密（Q515） |
| 網路 | 部署在 VPC 中；**Enhanced VPC Routing** 讓 COPY、UNLOAD 的流量強制走 VPC，可以搭配 VPC endpoint 與流量監控 |
| 權限 | IAM、資料庫使用者與角色、欄位與列層級權限，可以整合 Lake Formation |

### 資料怎麼進 Redshift

| 來源 | 常見做法 | 相關題號 |
|---|---|---|
| S3 上的檔案 | `COPY`；需要轉換時先用 **Glue ETL** 處理 | Q317、Q804 |
| 串流資料 | **Firehose** 直接投遞到 Redshift（先暫存在 S3 再 COPY），或用 streaming ingestion | Q59、Q225 |
| SaaS（Salesforce 等） | **Amazon AppFlow**，可以搭配 PrivateLink 避免經過公開網際網路 | Q821 |
| Aurora／RDS／DynamoDB | Zero-ETL integration、federated query 或 DMS | |
| 只想查 S3，不想載入 | Redshift Spectrum | |

### 使用情境

- **企業資料倉儲與 BI 報表**：整合 ERP、CRM、交易系統的歷史資料，搭配 QuickSight 或 Tableau 做 dashboard。
- **大量 clickstream 或日誌分析**：Kinesis → Firehose → S3 → Redshift（Q59、Q225）。
- **資料湖＋資料倉儲（lakehouse）**：熱資料放 Redshift，冷資料留在 S3 以 Spectrum 查詢。
- **分析師以 SQL 做機器學習**：Redshift ML（Q804）。
- **PB 級資料與大量並行查詢**：concurrency scaling、Redshift Serverless（Q515）。

### AWS 上的周邊服務

Redshift 很少單獨出現，通常是 AWS 分析架構中的一環：

```
來源                     攝取／轉換                     儲存與分析                  使用
─────────────────────────────────────────────────────────────────────────────────────────
RDS／Aurora／DynamoDB ─┐  DMS、Zero-ETL                ┌─► Redshift ──────────┐
SaaS（Salesforce…）  ──┼─► AppFlow                 ──┤                      ├─► QuickSight（BI）
串流（IoT、clickstream）┤  Kinesis、MSK、Firehose     │   S3 資料湖           ├─► SageMaker（ML）
檔案、日誌          ───┘  Glue ETL、EMR、DataBrew     └─► （Athena、Spectrum）┘
                          Glue Data Catalog、Lake Formation：中繼資料與權限治理
```

| 類別 | 服務 | 和 Redshift 的關係 |
|---|---|---|
| 資料攝取 | **Firehose**、**Kinesis Data Streams**、**MSK** | 串流資料投遞或直接攝取到 Redshift |
| 資料攝取 | **DMS** | 把地端或 RDS 資料庫遷移、持續複寫到 Redshift |
| 資料攝取 | **AppFlow** | 把 Salesforce、SAP、ServiceNow 等 SaaS 資料載入 Redshift |
| 資料轉換 | **Glue**（ETL、crawler、Data Catalog） | 轉換後載入 Redshift；Data Catalog 也是 Spectrum 與 Athena 共用的表格定義 |
| 資料轉換 | **EMR** | 用 Spark 大規模處理資料，可以讀寫 Redshift |
| 資料轉換 | **Glue DataBrew** | 以視覺化介面清理與準備資料，不用寫程式 |
| 資料湖治理 | **Lake Formation** | 集中管理 S3 資料湖與 Redshift 資料的細粒度權限 |
| 資料湖查詢 | **Athena** | 直接查 S3，和 Redshift Spectrum 共用 Glue Data Catalog |
| BI 視覺化 | **QuickSight** | 以 Redshift 為資料來源建立 dashboard |
| 機器學習 | **SageMaker** | Redshift ML 背後使用 SageMaker；也可以從 Redshift 讀取訓練資料 |
| 資料治理與協作 | **Amazon DataZone**、**SageMaker Unified Studio** | 資料目錄、資料分享與統一的分析開發環境 |
| 搜尋與日誌分析 | **OpenSearch Service** | 全文搜尋、日誌即時分析；和 Redshift 的結構化 SQL 分析互補 |

### 同等級的其他產品（AWS 以外）

如果在架構評估或客戶比較時需要對照，市場上和 Redshift 定位相近的雲端資料倉儲有：

| 產品 | 廠商 | 特色（概要） |
|---|---|---|
| **Snowflake** | Snowflake | 運算與儲存分離、可以跑在 AWS／Azure／GCP 上，資料分享功能強 |
| **BigQuery** | Google Cloud | 完全 serverless，依掃描量或保留容量計費 |
| **Azure Synapse Analytics／Microsoft Fabric** | Microsoft | Azure 的資料倉儲與分析平台；Fabric 是整合 OneLake 的新一代平台 |
| **Databricks SQL** | Databricks | 建立在 Delta Lake 的 lakehouse 架構，資料工程與 ML 整合深 |
| **Oracle Autonomous Data Warehouse** | Oracle | 自動調校與修補的託管資料倉儲 |
| **Teradata VantageCloud** | Teradata | 傳統企業資料倉儲廠商的雲端版本，常見於大型金融與電信業 |

> 這張表只做定位對照，各產品的功能與計價變動很快，實際評估請以各廠商的最新文件為準。SAA-C03 考試只會考 AWS 服務。

### 和其他 AWS 分析服務怎麼選

| 服務 | 定位 | 什麼時候選 |
|---|---|---|
| **Redshift** | 資料倉儲（MPP、欄式） | 經常性、複雜的 SQL 分析與報表，大量並行使用者，資料需要長期整合 |
| **Athena** | Serverless 互動式查詢，直接查 S3 | **偶爾、隨需**的查詢，不想建立或維護任何基礎設施，依掃描量付費（Q2、Q788、Q975） |
| **EMR** | 託管的 Hadoop／Spark 叢集 | 大規模資料處理、自訂的 Spark 作業，也可以讀取 Redshift 的資料（Q557） |
| **Glue** | Serverless ETL 與 Data Catalog | 轉換資料並載入 Redshift 或 S3（Q317、Q804） |
| **RDS／Aurora** | 關聯式 OLTP 資料庫 | 應用的交易資料；讀取負載重時加 read replica，不是改用 Redshift（Q14、Q144、Q269、Q864） |
| **DynamoDB＋DAX** | NoSQL＋微秒級快取 | 低延遲的鍵值存取，不是分析（Q578） |
| **OpenSearch** | 搜尋與日誌分析 | 全文搜尋、即時日誌與可觀測性分析 |
| **QuickSight** | BI 視覺化 | 在 Redshift、Athena 等資料來源上建立 dashboard |

### 容易混淆的地方

- **Redshift 不是 OLTP 資料庫**：題目要讓網站或應用的資料庫擴展讀取、降低延遲，答案是 read replica、Aurora Auto Scaling、ElastiCache 或 DAX；Redshift 在這些題目中都是錯誤選項（Q14、Q144、Q269、Q416、Q578、Q864）。
- **Redshift 和 Athena 的選擇**：「偶爾查詢 S3」「最省錢」「不改架構」選 Athena；「資料倉儲」「MPP」「頻繁的複雜分析」「大量 BI 使用者」選 Redshift。
- **Spectrum 和 Athena 都能查 S3**：Spectrum 要有 Redshift（叢集或 Serverless），適合和倉儲內的資料一起分析；Athena 完全獨立，不需要 Redshift。
- **Redshift ML 和 Athena 的差別**：Athena 只能呼叫已部署的 SageMaker 模型做推論，不能訓練；要用 SQL 建立並訓練模型選 Redshift ML（Q804）。
- **Serverless 的關鍵字**：題目要求「盡量 serverless」時，選 Redshift Serverless，而不是 provisioned cluster（Q804）。
- **跨 Region DR**：用 snapshot 的跨 Region 複製。如果叢集用 KMS 加密，要先在目的 Region 設定 snapshot copy grant。

### 考試判斷重點

- 「data warehouse」「OLAP」「petabyte-scale analytics」「MPP」「BI／reporting on historical data」→ **Redshift**。
- 「query data in S3 without loading」→ 只查 S3 選 **Athena**；要和 Redshift 資料一起查選 **Redshift Spectrum**。
- 「load streaming data into Redshift with least ops」→ **Firehose**。
- 「Salesforce／SaaS 資料進 Redshift」→ **AppFlow**。
- 「analysts build ML models using SQL」→ **Redshift ML**。

**相關題號**
- 選 Redshift：Q59、Q225、Q317、Q515、Q557、Q804、Q821
- Redshift 是錯誤選項：Q2、Q788、Q975（改選 Athena）；Q14、Q144、Q269、Q416、Q864（改選 read replica 或 Aurora）；Q578（改選 DAX）

> ⚠️ Q515 的投票較分散（BCE 60%、ACE 18%），詳見《詳解》。

---

## 12. AWS 資料庫服務總比較

### 一句話定位

AWS 的策略是 **purpose-built databases**：依資料結構與存取模式選擇專用的資料庫，而不是什麼都塞進一套關聯式資料庫。選型時依序問三個問題：

1. **資料長什麼樣子？**（結構：表格、鍵值、文件、圖、時間序列、全文）
2. **怎麼讀寫？**（目的：大量小交易 OLTP、大型彙總分析 OLAP、快取、搜尋）
3. **要多快、多大、多高可用？**（架構：單機或分散式、毫秒或微秒、單 Region 或多 Region）

### 全景總表

| 類型 | 服務 | 資料結構 | 主要目的 | 架構重點 | 延遲 | 典型情境 |
|---|---|---|---|---|---|---|
| **關聯式** | **RDS**（MySQL、PostgreSQL、MariaDB、Oracle、SQL Server、Db2） | 表格、Schema 固定、SQL、ACID | OLTP | 單一主庫；Multi-AZ 同步備援；最多 15 個 read replica（依引擎） | 毫秒 | ERP、CRM、電商訂單、既有應用直接搬遷 |
| | **Aurora**（MySQL／PostgreSQL 相容） | 同上 | 高效能 OLTP | 運算與儲存分離，儲存自動擴展到 128 TiB、跨 3 AZ 存 6 份；最多 15 個 Aurora Replica；Global Database；Serverless v2 | 毫秒 | 高流量的關鍵交易系統、跨 Region DR |
| | **Aurora DSQL** | 表格（PostgreSQL 相容） | 分散式 OLTP | Serverless、多 Region active-active，強一致性（2025 年 GA） | 毫秒 | 需要多 Region 同時寫入的關聯式應用 |
| **鍵值** | **DynamoDB** | 鍵值／文件（partition key＋sort key） | 大規模 OLTP | Serverless、分散式、自動分割；Global Tables 多 Region 多主 | 個位數毫秒 | 購物車、session、遊戲、IoT、高流量 API |
| **記憶體內** | **ElastiCache**（Valkey、Redis OSS、Memcached） | 鍵值、各種資料結構 | **快取** | 資料在記憶體；Valkey／Redis OSS 支援複寫與叢集模式 | 微秒到亞毫秒 | 資料庫查詢快取、session、排行榜、rate limit |
| | **MemoryDB** | 鍵值（Valkey／Redis OSS 相容） | **耐久的**記憶體內主資料庫 | 交易日誌跨多 AZ 持久保存 | 微秒讀、個位數毫秒寫 | 需要記憶體速度又不能遺失資料的主資料庫 |
| | **DAX** | DynamoDB 的資料 | DynamoDB 專用快取 | 與 DynamoDB API 相容，程式幾乎不用改 | 微秒 | DynamoDB 讀取熱點 |
| **文件** | **DocumentDB** | JSON 文件（MongoDB 相容） | 文件型 OLTP | 運算與儲存分離（架構類似 Aurora） | 毫秒 | 內容管理、商品目錄、使用者設定檔、從 MongoDB 遷移 |
| **寬欄位** | **Keyspaces** | 寬欄位（Apache Cassandra 相容、CQL） | 大規模寫入 | Serverless | 個位數毫秒 | 從 Cassandra 遷移、大量裝置資料 |
| **圖形** | **Neptune** | 節點與邊（Gremlin、openCypher、SPARQL） | 關係查詢 | 運算與儲存分離 | 毫秒 | 社群網路、推薦、詐欺偵測、知識圖譜、IT 資源關係圖 |
| **時間序列** | **Timestream for InfluxDB** | 時間戳記＋量測值 | 時間序列寫入與查詢 | 託管 InfluxDB | 毫秒 | IoT 感測器、監控指標、DevOps |
| **搜尋** | **OpenSearch Service** | 文件＋倒排索引 | 全文搜尋、日誌分析 | 叢集或 Serverless | 毫秒 | 網站搜尋、日誌與可觀測性、向量搜尋 |
| **資料倉儲** | **Redshift** | 表格（欄式儲存） | OLAP | MPP；provisioned 或 Serverless | 秒級（大查詢） | BI 報表、PB 級歷史資料分析（見第 11 章） |

> **服務現況**：
> - **Amazon QLDB**（帳本資料庫）已在 **2025-07-31 終止支援**，AWS 建議改用 Aurora PostgreSQL 搭配稽核設計。題庫中的 Q783 仍以 QLDB 為答案，考試時依題意作答即可。
> - **Timestream for LiveAnalytics** 已調整為不再開放給新客戶，新的時間序列工作負載以 Timestream for InfluxDB 為主。
> - ElastiCache 現在支援 **Valkey**（Redis 的開源分支），題目中的「ElastiCache for Redis」概念相同。

### 依「結構」比較

| 結構 | Schema | 查詢方式 | 擅長 | 不擅長 | 服務 |
|---|---|---|---|---|---|
| 表格（關聯式） | 固定，事先定義 | SQL、JOIN、交易 | 複雜查詢、資料一致性、報表 | 超大規模水平擴展寫入 | RDS、Aurora、Aurora DSQL |
| 鍵值 | 只需定義主鍵 | 依 key 讀寫、依 sort key 範圍查詢 | 極大規模、穩定低延遲 | 任意條件查詢、JOIN | DynamoDB、ElastiCache、MemoryDB |
| 文件 | 彈性，每份文件可不同 | 依欄位查詢、巢狀結構 | 結構多變的 JSON 資料 | 跨文件的複雜交易 | DocumentDB（DynamoDB 也能存文件） |
| 寬欄位 | 依查詢設計表格 | CQL | 大量寫入、依 partition 查詢 | 臨時性的複雜查詢 | Keyspaces |
| 圖形 | 節點、邊、屬性 | 走訪關係（多層 hop） | 「朋友的朋友」「誰和誰有關聯」 | 大量彙總統計 | Neptune |
| 時間序列 | 時間＋標籤＋數值 | 依時間範圍彙總 | 大量依時間寫入、降採樣 | 一般交易資料 | Timestream for InfluxDB |
| 全文索引 | 索引對應 | 關鍵字、模糊比對、相關性排序 | 搜尋、日誌分析 | 主要資料庫、交易 | OpenSearch |
| 欄式 | 表格 | SQL 彙總 | 大量資料的分析 | 單筆小交易 | Redshift |

### 依「目的」比較

| 目的 | 需求特徵 | 選擇 |
|---|---|---|
| 交易處理（OLTP） | 大量小交易、ACID、資料正確性 | RDS、Aurora；超大規模鍵值存取用 DynamoDB |
| 分析（OLAP） | 少量大查詢、彙總歷史資料 | Redshift；偶爾查 S3 用 Athena |
| 快取 | 降低資料庫負載、微秒到亞毫秒回應 | ElastiCache；DynamoDB 前面用 DAX |
| 搜尋 | 關鍵字、模糊搜尋、相關性排序 | OpenSearch |
| 關係分析 | 多層關聯、路徑查詢 | Neptune |
| 量測與監控資料 | 依時間大量寫入與彙總 | Timestream for InfluxDB |

### 依「架構」比較

| 架構面向 | RDS | Aurora | DynamoDB | ElastiCache | DocumentDB／Neptune |
|---|---|---|---|---|---|
| 擴展寫入 | 垂直擴展（換大 instance） | 垂直擴展；Serverless v2 自動調整容量 | **水平擴展**，自動分割 | 叢集模式分片 | 垂直擴展 |
| 擴展讀取 | Read replica（非同步） | Aurora Replica＋Auto Scaling，reader endpoint | 自動；可加 DAX | 增加 replica | 增加 replica |
| 同 Region 高可用 | **Multi-AZ**（同步備援，自動 failover） | 儲存跨 3 AZ，replica 可升級為主庫 | 預設跨 3 AZ | Multi-AZ＋自動 failover | 儲存跨 3 AZ |
| 跨 Region | 跨 Region read replica | **Global Database**（RPO 通常低於 1 秒） | **Global Tables**（多 Region 多主） | Global Datastore（Valkey／Redis OSS） | Global Cluster |
| 容量模式 | Provisioned | Provisioned 或 Serverless v2 | On-demand 或 provisioned | 節點或 Serverless | Provisioned（Neptune 也有 Serverless） |
| 管理負擔 | 中（選 instance、管引擎版本） | 中低 | 低（serverless） | 中低 | 中低 |

### 選型決策流程

```
需要 SQL、JOIN、ACID 交易嗎？
├─ 是 → 是分析（OLAP）還是交易（OLTP）？
│        ├─ 分析 → Redshift（偶爾查 S3：Athena）
│        └─ 交易 → 需要特定商用引擎或直接搬遷？ → RDS
│                  要更高效能、自動擴展儲存、跨 Region 低 RPO？ → Aurora
│                  要多 Region 同時寫入的關聯式？ → Aurora DSQL
└─ 否 → 資料結構與存取模式是什麼？
         ├─ 依 key 存取、超大規模、serverless → DynamoDB（要微秒加 DAX）
         ├─ 快取或微秒回應 → ElastiCache（要耐久保存：MemoryDB）
         ├─ JSON 文件、MongoDB 相容 → DocumentDB
         ├─ Cassandra 相容 → Keyspaces
         ├─ 關係與路徑查詢 → Neptune
         ├─ 時間序列 → Timestream for InfluxDB
         └─ 全文搜尋、日誌分析 → OpenSearch
```

### 題目關鍵字對照

| 題目關鍵字 | 答案 | 相關題號 |
|---|---|---|
| 「MySQL／PostgreSQL 相容」「自動擴展讀取」「高可用」 | Aurora＋Aurora Auto Scaling | Q14、Q565 |
| 「報表拖慢主庫」「分析師的唯讀查詢」 | Read replica／Aurora Replica | Q144、Q269、Q864 |
| 「不想選 instance type」「流量不可預測」的關聯式資料庫 | Aurora Serverless v2 | Q314、Q596、Q824 |
| 「連線數過多」「failover 時間要縮短」 | RDS Proxy | Q755、Q958 |
| 「跨 Region、RPO 秒級、RTO 分鐘級」的關聯式資料庫 | Aurora Global Database | Q273、Q896 |
| 「毫秒延遲」「serverless」「scale to millions」「key-value」 | DynamoDB | Q33、Q735 |
| 「DynamoDB 要從毫秒降到微秒」 | DAX | Q578 |
| 「降低 RDS 讀取負載」「商品目錄不常變動」「session 存放」 | ElastiCache | Q999 |
| 「MongoDB 相容」 | DocumentDB | Q198 |
| 「關係」「圖」「推薦」「詐欺偵測」 | Neptune | Q850 |
| 「全文搜尋」「日誌即時分析與視覺化」 | OpenSearch | Q676、Q968 |
| 「不可變、可用密碼學驗證的變更紀錄」 | QLDB（已終止支援，考試仍可能出現） | Q783 |
| 「資料倉儲」「PB 級分析」「MPP」 | Redshift | Q59、Q225、Q804 |

### 容易混淆的地方

- **RDS Multi-AZ 和 read replica**：Multi-AZ 是**高可用**，用同步備援，standby 平時不提供讀取（Multi-AZ DB cluster 例外，它的兩個 standby 可以讀）；read replica 是**擴展讀取**，用非同步複寫。
- **Aurora 和 RDS**：兩者都是 RDS 家族。Aurora 的儲存層是 AWS 自建的分散式儲存，failover 更快、replica 延遲更低、儲存自動擴展；RDS 則支援 Oracle、SQL Server、Db2 等商用引擎。
- **DynamoDB 不是「不能查詢」**：DynamoDB 可以用 partition key 與 sort key 查詢，也能建 GSI／LSI 換一個 key 查詢；它做不到的是任意條件的 JOIN 與臨時性的複雜分析，這類需求要匯出到 S3 再用 Athena 或 Redshift。
- **ElastiCache 和 MemoryDB**：ElastiCache 定位是**快取**，資料可能遺失；MemoryDB 是**主資料庫**，資料耐久保存。
- **DAX 和 ElastiCache**：DAX 只能搭配 DynamoDB，與 DynamoDB API 相容；ElastiCache 可以搭配任何資料來源，但應用要自己寫快取邏輯（例如 lazy loading）。
- **Redshift 和 RDS／Aurora**：網站讀取變慢要擴展的是 OLTP 資料庫（read replica、快取），不是改用 Redshift（見第 11 章）。
- **OpenSearch 不是主要資料庫**：它適合搜尋與分析，原始資料通常另外存在 DynamoDB、RDS 或 S3，再同步到 OpenSearch 建立索引。

**相關題號**：Q14、Q33、Q59、Q144、Q198、Q225、Q269、Q273、Q314、Q565、Q578、Q596、Q676、Q735、Q755、Q783、Q804、Q824、Q850、Q864、Q896、Q958、Q968、Q999

---

## 13. AWS Config、CloudTrail、CloudWatch 的關係

### 一句話定位

三者都和「監控」有關，但回答的是不同的問題：

| 服務 | 回答的問題 | 比喻 |
|---|---|---|
| **CloudWatch** | 系統**現在狀況如何**？效能、用量、錯誤是否異常？ | 健康檢查儀表板與警報器 |
| **CloudTrail** | **誰**在**什麼時候**、從**哪裡**、呼叫了**哪個 API**？ | 監視器錄影 |
| **AWS Config** | 資源**現在的設定是什麼**、**怎麼變過**、**合不合規**？ | 資產清冊＋變更紀錄＋稽核員 |

> 記法：**CloudWatch 看效能、CloudTrail 看行為、Config 看設定。**

### 用同一個事件看三者分工

假設有人在 security group 開放了 `0.0.0.0/0` 的 SSH（port 22）：

```
工程師呼叫 AuthorizeSecurityGroupIngress
        │
        ├──► CloudTrail：記錄「user/alice 在 10:05 從 203.0.113.10 呼叫了 AuthorizeSecurityGroupIngress，參數是 0.0.0.0/0:22」
        │         │
        │         └──► EventBridge（API 事件）──► Lambda 自動撤銷規則（選用）
        │
        ├──► AWS Config：記錄 SG 的新設定（組態項目，並關聯上述 CloudTrail 事件）
        │         │
        │         └──► Config rule restricted-ssh 判定 NON_COMPLIANT
        │                   └──► EventBridge ──► SNS 通知／SSM Automation 自動修復
        │
        └──► CloudWatch：CloudTrail 送進 CloudWatch Logs 後，metric filter 計數 SG 變更
                  └──► CloudWatch alarm ──► SNS 通知；也可以放到 dashboard
```

- 想知道**是誰改的** → CloudTrail（Q395）。
- 想知道**改完之後變成什麼、是否違規** → Config（Q774）。
- 想**即時告警、畫成圖表** → CloudWatch。

### 三個服務各自的重點

**CloudTrail**

| 項目 | 內容 |
|---|---|
| 記錄內容 | API 呼叫的身分（userIdentity）、時間、來源 IP、參數、結果（成功或錯誤碼） |
| Management events | 控制面的操作，例如建立 EC2、修改 SG、建立 IAM user。**預設記錄**，Event history 免費保留 **90 天** |
| Data events | 資料面的操作，例如 S3 的 GetObject／PutObject、Lambda Invoke。**預設不記錄**，要另外開啟並計費 |
| Insights events | 偵測 API 呼叫量或錯誤率的異常 |
| Trail | 把事件長期存到 **S3**，也可以送到 CloudWatch Logs；可以建立**多 Region trail** 與**組織 trail** |
| 完整性 | **Log file integrity validation** 產生 digest 檔，可以驗證日誌是否被竄改 |
| 查詢 | 用 **Athena** 查 S3 中的日誌（Q524），或用 **CloudTrail Lake** 以 SQL 查詢 |
| 防止被關閉 | 用 **SCP** 拒絕 `cloudtrail:StopLogging`、`DeleteTrail`、`UpdateTrail`（Q619） |

**CloudWatch**

| 項目 | 內容 |
|---|---|
| Metrics | 各服務的效能指標。EC2 預設 5 分鐘一筆，開啟 **detailed monitoring** 後為 1 分鐘（Q910）。記憶體與磁碟使用率要安裝 **CloudWatch agent** |
| Alarms | 指標超過門檻時通知或執行動作，例如 Auto Scaling、EC2 自動復原（Q757）。**Composite alarm** 可以用 AND／OR 組合多個 alarm，減少誤報（Q150） |
| Logs | 集中收集應用、VPC Flow Logs、CloudTrail 等日誌。**Metric filter** 把日誌轉成指標（Q232）；**subscription filter** 把日誌即時串流到 OpenSearch、Lambda、Firehose（Q117）；**Logs Insights** 以查詢語法分析日誌 |
| Dashboards | 視覺化，可以跨帳號、跨 Region |
| 其他 | Container Insights（Q615、Q695）、cross-account observability（Q748）、Synthetics、Application Signals |
| EventBridge | 原名 **CloudWatch Events**，負責事件路由；CloudTrail、Config 的事件都經由它觸發後續動作 |

**AWS Config**：見第 1 章與第 9 章。重點是組態記錄、組態歷史、Config Rules、自動修復與 Aggregator。

### 三者如何串在一起

| 整合 | 用途 | 相關題號 |
|---|---|---|
| CloudTrail → **EventBridge** → Lambda | 某個 API 被呼叫時立即觸發動作，例如建立資源後自動加標籤 | Q653 |
| CloudTrail → **CloudWatch Logs** → metric filter → alarm | 偵測特定行為並告警，例如 root 登入、未授權的 API 呼叫、SG 變更（CIS 基準的常見做法） | |
| CloudTrail → **S3** → Athena | 事後調查與稽核查詢 | Q524 |
| Config 的組態項目 ↔ **CloudTrail 事件** | Config 的資源時間軸會顯示造成變更的 CloudTrail 事件，可以從「變成什麼」追到「誰改的」 | Q34、Q318 |
| Config → **EventBridge** → SNS／Lambda | 合規狀態改變時通知或觸發修復 | Q774 |
| Config → **SSM Automation** | 不合規時自動修復 | |
| VPC Flow Logs → **CloudWatch Logs** → metric filter | 偵測 SSH／RDP 連線並通知 | Q232 |

### 比較總表

| | CloudWatch | CloudTrail | AWS Config |
|---|---|---|---|
| 關注點 | 效能、可用性、日誌 | 使用者與服務的 API 行為 | 資源設定與合規 |
| 資料型態 | 時間序列指標、日誌、事件 | API 事件紀錄 | 組態項目（某一時間點的資源設定快照） |
| 典型問題 | CPU 為什麼飆高？錯誤率有沒有上升？ | 誰刪了這個 bucket？誰改了 IAM policy？ | 這個 SG 昨天的設定是什麼？有多少 EBS 沒加密？ |
| 即時性 | 即時（秒到分鐘） | 通常數分鐘內送達 | 設定變更後評估 |
| 能否自動處理 | Alarm 觸發 Auto Scaling、EC2 復原、SNS | 經 EventBridge 觸發 Lambda | Rule 搭配 SSM Automation 修復 |
| 預設狀態 | 基本指標預設就有 | Management events 的 90 天 Event history 預設就有 | 要**手動啟用** recorder |
| 範圍 | Region（dashboard 可跨帳號、跨 Region） | Region；可建立多 Region trail 與組織 trail | Region；用 Aggregator 跨帳號、跨 Region |

### 容易混淆的地方

- **「追蹤組態變更」和「追蹤 API 呼叫」是兩件事**：題目兩者都要時，答案是 **Config＋CloudTrail**（Q34、Q318）。
- **找「是誰」一定是 CloudTrail**：Config 只記錄設定變成什麼，不會直接回答是哪位使用者做的（Q395）。
- **CloudWatch 不記錄 API 行為**：CloudWatch Logs 可以「存放」CloudTrail 的日誌，但產生紀錄的是 CloudTrail。
- **三者都只能偵測，不能預防**：要阻止某些動作發生，用 SCP、IAM policy 或 Control Tower proactive controls。CloudTrail 本身要防止被關閉，也是靠 SCP（Q619）。
- **S3 物件層級的存取要開 data events**：預設的 trail 只記錄 management events，查不到誰下載了哪個物件。
- **EventBridge 是事件匯流排**：它本身不監控，負責把 CloudTrail、Config、各服務的事件轉送到 Lambda、SNS、SQS 等目標。

### 考試判斷重點

| 題目關鍵字 | 答案 |
|---|---|
| 「who made the change」「audit API calls」「user activity」 | CloudTrail |
| 「configuration history」「compliance」「noncompliant resources」 | AWS Config |
| 「metrics」「alarm」「CPU／memory utilization」「dashboard」「log aggregation」 | CloudWatch |
| 「track configuration changes **and** API calls」 | Config＋CloudTrail |
| 「API 被呼叫時立即自動處理」 | CloudTrail＋EventBridge＋Lambda |
| 「偵測特定日誌內容並告警」 | CloudWatch Logs metric filter＋alarm |
| 「查詢歷史 API 紀錄、分析 Access Denied」 | Athena 查 S3 的 CloudTrail 日誌 |

**相關題號**
- CloudTrail：Q34、Q318、Q395、Q524、Q619、Q653
- AWS Config：Q34、Q318、Q774（另見第 1 章、第 9 章）
- CloudWatch：Q117、Q150、Q232、Q615、Q695、Q748、Q757、Q910

---

## 更新紀錄

- 2026-11-14：建立文件，收錄 AWS Config、S3 Glacier Deep Archive、S3 IA、RPO 與 RTO。
- 2026-11-14：新增「Elastic Load Balancing（ALB、NLB、GWLB、CLB）」。
- 2026-11-15：新增「AWS Network Firewall」。
- 2026-11-15：第 1 章擴充為「AWS Config 與 Config Rules」，補充規則類型、觸發方式、評估模式、修復與規模化部署。
- 2026-11-15：新增「Amazon Cognito（User Pool 與 Identity Pool）」。
- 2026-11-15：新增「RDS Performance Insights」，附註它正移轉到 CloudWatch Database Insights（終止日期未經 AWS 官方文件確認）。
- 2026-11-15：新增「資源標籤治理與 AWS Config required-tags」（以 Q31 為例），並更正 Q31 解析中關於自動修復的說法。
- 2026-11-15：第 9 章補充「Cost Explorer 和 AWS Config 的關係」。
- 2026-11-15：新增「Kinesis、DynamoDB、Lambda 的關係與使用情境」。
- 2026-11-15：新增「Amazon Redshift」，含 AWS 周邊服務與同等級產品對照。
- 2026-11-15：新增「AWS 資料庫服務總比較」，依結構、目的、架構比較，並註明 QLDB 終止支援與 Timestream for LiveAnalytics 的狀態。
- 2026-11-15：新增「AWS Config、CloudTrail、CloudWatch 的關係」。

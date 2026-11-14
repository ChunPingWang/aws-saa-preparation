# AWS SAA-C03 觀念釐清

> 本文件整理準備 SAA-C03 時逐一提問的觀念，作為《SAA-C03 考題詳解》與《SAA-C03 產品概念地圖》的補充。每個主題包含功能說明、使用情境、容易混淆的地方，以及對應的考題題號，可以回到詳解文件練習。
>
> 文中的價格皆為 us-east-1 的參考值，各 Region 不同，AWS 也會調整，請以官方價目表為準。

## 目錄

1. [AWS Config](#1-aws-config)
2. [S3 Glacier Deep Archive](#2-s3-glacier-deep-archive)
3. [S3 Infrequent Access（Standard-IA 與 One Zone-IA）](#3-s3-infrequent-accessstandard-ia-與-one-zone-ia)
4. [RPO 與 RTO](#4-rpo-與-rto)
5. [Elastic Load Balancing（ALB、NLB、GWLB、CLB）](#5-elastic-load-balancingalbnlbgwlbclb)

---

## 1. AWS Config

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

### 考試判斷重點

看到「detect / track configuration changes」「compliance」「noncompliant resources」「ensure all resources are tagged/encrypted」，並且要「最少維運」時，答案通常是 **AWS Config 受管規則（＋SNS 通知或 SSM 自動修復）**。

**相關題號**：Q26、Q31、Q34、Q318、Q682、Q689、Q774

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

## 更新紀錄

- 2026-11-14：建立文件，收錄 AWS Config、S3 Glacier Deep Archive、S3 IA、RPO 與 RTO。
- 2026-11-14：新增「Elastic Load Balancing（ALB、NLB、GWLB、CLB）」。

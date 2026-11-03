-- Lab 16：Athena 直接查詢 S3 上的 CSV（Schema-on-Read，依掃描量計費）
-- 把 <ACCOUNT_ID> 換成你的帳號 ID（或 scripts/16-governance-data.sh 會自動代入）

CREATE DATABASE IF NOT EXISTS saa_lab;

CREATE EXTERNAL TABLE IF NOT EXISTS saa_lab.orders (
  order_id   int,
  customer   string,
  region     string,
  amount     int,
  created_at string
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
LOCATION 's3://saa-lab-athena-<ACCOUNT_ID>/orders/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- 金額大於 100 的訂單，依金額排序
SELECT order_id, customer, region, amount
FROM saa_lab.orders
WHERE amount > 100
ORDER BY amount DESC;

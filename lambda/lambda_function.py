"""SAA Lab 8：訂單 API（Lambda + DynamoDB）

事件格式：
  建立：{"action": "create", "order_id": "A1001", "customer": "rex", "amount": 120}
  查詢：{"action": "get", "order_id": "A1001"}
"""
import datetime
import json
import os
import uuid

import boto3

TABLE = boto3.resource("dynamodb").Table(os.environ.get("TABLE_NAME", "saa-orders"))


def lambda_handler(event, context):
    action = event.get("action", "create")

    if action == "create":
        item = {
            "order_id": event.get("order_id") or str(uuid.uuid4())[:8],
            "customer": event.get("customer", "demo"),
            "amount": int(event.get("amount", 0)),
            "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        }
        TABLE.put_item(Item=item)
        return {"statusCode": 201, "body": json.dumps(item)}

    if action == "get":
        resp = TABLE.get_item(Key={"order_id": event["order_id"]})
        item = resp.get("Item")
        return {
            "statusCode": 200 if item else 404,
            "body": json.dumps(item or {}, default=str),
        }

    return {"statusCode": 400, "body": json.dumps({"error": "unknown action"})}

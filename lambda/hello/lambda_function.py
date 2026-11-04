import json, os

def lambda_handler(event, context):
    qs = event.get("queryStringParameters") or {}
    name = qs.get("name", "SAA")
    body = {"message": f"Hello, {name}!", "path": event.get("path"), "method": event.get("httpMethod"), "requestId": context.aws_request_id}
    return {"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body)}

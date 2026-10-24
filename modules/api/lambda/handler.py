"""Tier 2: task API.

API Gateway has already checked the caller's Cognito token before this runs,
and it passes the verified token claims in the event. The user ID comes from
those claims, never from the request body, so a user can only touch their own tasks.

Routes:
  GET    /tasks            list the caller's tasks
  POST   /tasks            create a task   {"title": "..."}
  DELETE /tasks/{taskId}   delete one of the caller's tasks
"""
import base64
import json
import logging
import os
import time
import uuid
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Created once per container and reused across invocations (faster warm starts)
table = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])


def to_json(value):
    if isinstance(value, Decimal):
        return int(value)
    raise TypeError(f"Cannot serialize {type(value)}")


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=to_json),
    }


def read_body(event):
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode()
    return json.loads(raw)


def handler(event, context):
    route = event.get("routeKey")
    claims = event["requestContext"]["authorizer"]["jwt"]["claims"]
    user_id = claims["sub"]

    # One structured log line per request, searchable in CloudWatch Logs Insights
    logger.info(json.dumps({"route": route, "user": user_id, "requestId": context.aws_request_id}))

    try:
        if route == "GET /tasks":
            result = table.query(KeyConditionExpression=Key("userId").eq(user_id))
            items = sorted(result["Items"], key=lambda item: item["createdAt"])
            return respond(200, items)

        if route == "POST /tasks":
            try:
                data = read_body(event)
            except (ValueError, UnicodeDecodeError):
                return respond(400, {"error": "Body must be JSON"})
            title = str(data.get("title", "")).strip()
            if not title or len(title) > 200:
                return respond(400, {"error": "title is required (1-200 characters)"})
            item = {
                "userId": user_id,
                "taskId": str(uuid.uuid4()),
                "title": title,
                "createdAt": int(time.time()),
            }
            table.put_item(Item=item)
            logger.info(json.dumps({"event": "task_created", "taskId": item["taskId"]}))
            return respond(201, item)

        if route == "DELETE /tasks/{taskId}":
            task_id = event["pathParameters"]["taskId"]
            # The key includes userId, so this can only ever delete the caller's own task
            result = table.delete_item(Key={"userId": user_id, "taskId": task_id}, ReturnValues="ALL_OLD")
            if "Attributes" not in result:
                return respond(404, {"error": "Task not found"})
            logger.info(json.dumps({"event": "task_deleted", "taskId": task_id}))
            return respond(200, {"deleted": task_id})

        return respond(404, {"error": "Route not found"})

    except Exception:
        # Full stack trace goes to CloudWatch; the caller only sees a generic message
        logger.exception("Request failed")
        return respond(500, {"error": "Internal server error"})

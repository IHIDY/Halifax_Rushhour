"""
Halifax Transit Delay Score — API Handler Lambda

GET /v1/routes/{route_id}  — CTRS score and history
GET /v1/health             — health check
"""

import json
import os
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key


def _log(level: str, message: str, **kwargs):
    print(json.dumps({"level": level, "message": message, **kwargs}))

TABLE_NAME = os.environ["TABLE_NAME"]
MAX_ITEMS  = 10

dynamodb = boto3.resource("dynamodb", region_name="ca-central-1")
table    = dynamodb.Table(TABLE_NAME)


class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "max-age=15",
        },
        "body": json.dumps(body, cls=DecimalEncoder),
    }


def handler(event, context):
    resource = event.get("resource", "")

    # ── Health check ──────────────────────────────────────────────────────────
    if resource == "/health":
        _log("INFO", "health check ok")
        return _response(200, {
            "status":    "ok",
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        })

    # ── Route score query ─────────────────────────────────────────────────────
    path_params = event.get("pathParameters") or {}
    route_id    = path_params.get("route_id", "").strip()

    if not route_id:
        _log("WARNING", "missing route_id parameter")
        return _response(400, {"error": "route_id path parameter is required"})

    try:
        result = table.query(
            KeyConditionExpression=Key("route_id").eq(route_id),
            ScanIndexForward=False,
            Limit=MAX_ITEMS,
        )
        items = result.get("Items", [])
    except Exception as exc:
        # Graceful degradation: DynamoDB unavailable → 503 with meaningful message
        _log("ERROR", "dynamodb query failed", route_id=route_id, error=str(exc))
        return _response(503, {
            "error":   "Score data temporarily unavailable",
            "message": "The data store is unreachable. Cached scores remain valid for up to 15 seconds.",
        })

    if not items:
        _log("INFO", "route not found", route_id=route_id)
        return _response(404, {
            "route_id": route_id,
            "message":  "No data found. Try again after the next ingestion cycle.",
        })

    latest = items[0]
    _log("INFO", "query success", route_id=route_id, score=int(latest["score"]))
    return _response(200, {
        "route_id":  route_id,
        "timestamp": latest["timestamp"],
        "ctrs": {
            "score":       latest["score"],
            "otr":         latest["otr"],
            "mean_excess": latest["mean_excess"],
            "std_dev":     latest["std_dev"],
            "n_stops":     latest["n_stops"],
        },
        "history": items,
    })

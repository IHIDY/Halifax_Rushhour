"""
DynamoDB Streams → S3 Archival Lambda

Triggered by every INSERT on TransitScores table.
Writes each score record to S3 in Hive-partitioned JSON format,
compatible with Athena for ad-hoc time-series queries.

S3 path: scores/year=YYYY/month=MM/day=DD/route={route_id}/{timestamp}.json
"""

import json
import os
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.types import TypeDeserializer

BUCKET      = os.environ["DATA_LAKE_BUCKET"]
PREFIX      = "scores"

s3           = boto3.client("s3", region_name="ca-central-1")
deserializer = TypeDeserializer()


def _deserialize(record: dict) -> dict:
    return {k: deserializer.deserialize(v) for k, v in record.items()}


def _s3_key(item: dict) -> str:
    """
    Hive-style partitioned key for Athena compatibility.
    scores/year=2026/month=07/day=04/route=63/2026-07-04T00:58:05Z.json
    """
    ts  = item.get("timestamp", datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    dt  = datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
    rid = item.get("route_id", "unknown")
    return (
        f"{PREFIX}/"
        f"year={dt.year:04d}/"
        f"month={dt.month:02d}/"
        f"day={dt.day:02d}/"
        f"route={rid}/"
        f"{ts}.json"
    )


def handler(event, context):
    written = 0

    for record in event.get("Records", []):
        if record["eventName"] != "INSERT":
            continue

        raw  = record["dynamodb"].get("NewImage", {})
        item = _deserialize(raw)

        key  = _s3_key(item)
        body = json.dumps(item, default=str)

        s3.put_object(
            Bucket      = BUCKET,
            Key         = key,
            Body        = body,
            ContentType = "application/json",
        )
        written += 1

    print(f"INFO: archived {written} records to s3://{BUCKET}/{PREFIX}/")
    return {"archived": written}

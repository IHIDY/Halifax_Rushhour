"""
Halifax Transit GTFS-RT Ingestor Lambda

Triggered every 1 minute by EventBridge.
Computes Composite Transit Reliability Score (CTRS, 0-100) per route
and writes to DynamoDB with a 24-hour TTL.
"""

import json
import math
import os
import statistics
import time
import urllib.request
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from google.transit import gtfs_realtime_pb2


def _log(level: str, message: str, **kwargs):
    print(json.dumps({"level": level, "message": message, **kwargs}))

TABLE_NAME = os.environ["TABLE_NAME"]
GTFS_URL   = os.environ.get("GTFS_URL", "https://gtfs.halifax.ca/realtime/TripUpdate/TripUpdates.pb")
TTL_HOURS  = int(os.environ.get("SCORE_TTL_H", "24"))

dynamodb = boto3.resource("dynamodb", region_name="ca-central-1")
table    = dynamodb.Table(TABLE_NAME)

# ── GTFS-RT industry-standard thresholds ─────────────────────────────────────
EARLY_BOUND       = -60    # > 1 min early = schedule adherence violation
ON_TIME_LATE      =  60    # ≤ 1 min late  = on-time  (GTFS standard)
SEVERITY_HALFLIFE = 120.0  # exponential half-life: 2 min excess delay → SI halved
CONSIST_HALFLIFE  = 180.0  # exponential half-life: 3 min std-dev      → CI halved

# Composite weights (must sum to 1.0)
W_OTR         = 0.50   # On-Time Rate      — primary industry KPI
W_SEVERITY    = 0.30   # Severity Index    — non-linear excess delay penalty
W_CONSISTENCY = 0.20   # Consistency Index — penalises erratic headways


# ── CTRS core ─────────────────────────────────────────────────────────────────

def _ctrs(delays: list[float]) -> dict:
    """
    Composite Transit Reliability Score (CTRS), 0-100.

    Component 1 — On-Time Rate (OTR, weight=0.50):
        Fraction of stop updates within GTFS on-time window [-60s, +60s].
        Industry standard used by TfL, MTA, TransLink.

    Component 2 — Severity Index (SI, weight=0.30):
        Exponential decay on mean excess delay beyond the on-time threshold.
        SI = exp(-mean_excess / 120) captures the non-linear passenger
        perception of waiting (based on Bates et al., 2001 schedule delay model).

    Component 3 — Consistency Index (CI, weight=0.20):
        Exponential decay on delay standard deviation.
        CI = exp(-std_dev / 180) penalises erratic service even when the
        mean delay looks acceptable (Welding, 1957 bunching theory).

    Pre-processing: top 2% of delay values are clipped to remove GPS outliers.
    """
    n = len(delays)
    if n == 0:
        return {"score": 0, "otr": 0.0, "mean_excess": 0.0, "std_dev": 0.0, "n_stops": 0}

    # Remove top-2% GPS outliers before scoring
    clip_k   = max(0, int(n * 0.02))
    filtered = sorted(delays)[:n - clip_k] if clip_k else sorted(delays)
    m        = len(filtered)

    # 1. On-Time Rate
    on_time = sum(1 for d in filtered if EARLY_BOUND <= d <= ON_TIME_LATE)
    otr     = on_time / m

    # 2. Severity Index
    mean_excess = sum(max(0.0, d - ON_TIME_LATE) for d in filtered) / m
    severity    = math.exp(-mean_excess / SEVERITY_HALFLIFE)

    # 3. Consistency Index
    std_dev     = statistics.stdev(filtered) if m > 1 else 0.0
    consistency = math.exp(-std_dev / CONSIST_HALFLIFE)

    # 4. Weighted composite → 0-100
    score = max(0, min(100, round(100.0 * (
        W_OTR * otr + W_SEVERITY * severity + W_CONSISTENCY * consistency
    ))))

    return {
        "score":       score,
        "otr":         round(otr * 100, 1),   # % of stops on time
        "mean_excess": round(mean_excess, 1),  # avg seconds over threshold
        "std_dev":     round(std_dev, 1),      # delay spread in seconds
        "n_stops":     m,
    }


# ── GTFS-RT parsing ───────────────────────────────────────────────────────────

def _collect_route_delays(feed: gtfs_realtime_pb2.FeedMessage) -> dict[str, list[float]]:
    route_delays: dict[str, list[float]] = {}

    for entity in feed.entity:
        if not entity.HasField("trip_update"):
            continue
        route_id = entity.trip_update.trip.route_id
        if not route_id:
            continue

        for stu in entity.trip_update.stop_time_update:
            if stu.HasField("arrival") and stu.arrival.HasField("delay"):
                route_delays.setdefault(route_id, []).append(float(stu.arrival.delay))
            elif stu.HasField("departure") and stu.departure.HasField("delay"):
                route_delays.setdefault(route_id, []).append(float(stu.departure.delay))

    return route_delays


# ── DynamoDB write ────────────────────────────────────────────────────────────

def _write_scores(results: dict[str, dict], ts: str, ttl_epoch: int) -> int:
    # Use individual put_item() to match IAM policy (PutItem only).
    # batch_writer() internally calls BatchWriteItem — a different API.
    written = 0
    for route_id, m in results.items():
        table.put_item(Item={
            "route_id":    route_id,
            "timestamp":   ts,
            "score":       Decimal(str(m["score"])),
            "otr":         Decimal(str(m["otr"])),
            "mean_excess": Decimal(str(m["mean_excess"])),
            "std_dev":     Decimal(str(m["std_dev"])),
            "n_stops":     m["n_stops"],
            "ttl_epoch":   ttl_epoch,
        })
        written += 1
    return written


# ── Handler ───────────────────────────────────────────────────────────────────

def handler(event, context):
    now       = datetime.now(timezone.utc)
    ts        = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    ttl_epoch = int(time.time()) + TTL_HOURS * 3600

    req = urllib.request.Request(GTFS_URL, headers={"User-Agent": "CSCI4149-Transit/1.0"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        raw = resp.read()

    feed = gtfs_realtime_pb2.FeedMessage()
    feed.ParseFromString(raw)

    route_delays = _collect_route_delays(feed)
    if not route_delays:
        _log("WARNING", "no scorable trip updates in feed", timestamp=ts)
        return {"statusCode": 204, "body": "no data"}

    results = {rid: _ctrs(delays) for rid, delays in route_delays.items()}
    count   = _write_scores(results, ts, ttl_epoch)
    _log("INFO", "ingestion complete", routes_written=count, timestamp=ts)

    return {"statusCode": 200, "body": f"wrote {count} scores"}

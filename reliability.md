# Halifax Transit Pipeline — Reliability Design

## Multi-AZ Deployment

All components are AWS-managed serverless services that operate across multiple
Availability Zones in ca-central-1 (3 AZs: cac1-az1, cac1-az2, cac1-az4)
without any explicit configuration:

| Component     | Multi-AZ mechanism                                      |
|---------------|---------------------------------------------------------|
| API Gateway   | Regional endpoint, load-balanced across all AZs         |
| Lambda        | Scheduler places invocations across AZs automatically   |
| DynamoDB      | Data replicated across 3 AZs; single-AZ failure = zero impact |
| S3            | Object durability 99.999999999% across >= 3 AZs         |
| EventBridge   | Fully managed, inherently multi-AZ                      |

A single AZ failure causes zero downtime for any component in this stack.

---

## Health Checks

A dedicated health endpoint is available at:

```
GET /v1/health
→ 200 { "status": "ok", "timestamp": "2026-07-04T00:00:00Z" }
```

This endpoint is excluded from the 15-second API Gateway cache, ensuring it
always reflects live Lambda availability. CloudWatch alarms (defined in
monitoring.tf) provide automated health monitoring with SNS notifications for:

- Ingestor error rate > 0 for 2 consecutive minutes
- API error rate > 5 errors in 5 minutes
- API p95 latency > 200ms
- DynamoDB throttled requests > 0
- Streams Lambda errors > 0

---

## Graceful Degradation Strategy

The CQRS architecture provides natural fault isolation between the write path
(ingestor) and the read path (API). Each failure mode degrades gracefully:

| Failure                  | User impact                                         | Recovery              |
|--------------------------|-----------------------------------------------------|-----------------------|
| Ingestor Lambda fails    | API serves existing DynamoDB scores (up to 24h TTL) | Auto-retry next cycle |
| GTFS feed unreachable    | Same as above — stale scores served                 | Auto-retry next cycle |
| DynamoDB single-AZ fault | Zero — other AZs serve reads automatically          | Automatic             |
| DynamoDB fully down      | API returns HTTP 503 with descriptive message       | DynamoDB SLA recovery |
| API Lambda cold start    | API Gateway cache serves last response for 15s      | Automatic warm-up     |
| Streams Lambda fails     | Live scores unaffected; S3 archival lags by <24h    | Manual redeploy       |

When DynamoDB is unreachable, the API Lambda returns:
```json
{
  "error": "Score data temporarily unavailable",
  "message": "The data store is unreachable. Cached scores remain valid for up to 15 seconds."
}
```

---

## RTO and RPO

### RPO — Recovery Point Objective

**RPO = 5 minutes**

DynamoDB Point-In-Time Recovery (PITR) is enabled, allowing restore to any
second within the last 35 days. In the worst case (full table corruption), a
maximum of 5 minutes of score data is lost — one ingestion cycle.

S3 data lake provides a secondary recovery source: all scores are archived to
S3 within seconds of DynamoDB write via Streams, and retained indefinitely
under the four-tier lifecycle policy.

### RTO — Recovery Time Objective

**RTO = 3 minutes**

All infrastructure is defined as Terraform IaC. Full environment reconstruction
from zero requires:

| Step                          | Duration   |
|-------------------------------|------------|
| `terraform apply` (cold)      | ~2 minutes |
| Lambda warm-up (first invoke) | ~30 seconds|
| API Gateway cache population  | ~15 seconds|
| **Total**                     | **~3 minutes** |

For component-level failures (Lambda crash, single-AZ fault), RTO is
effectively zero — AWS automatically retries or routes around the failure
without operator intervention.

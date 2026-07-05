# Halifax Transit Pipeline — Runbook

## Deploy

```
make deploy
```

Builds Lambda zips, runs `terraform init` + `terraform apply -auto-approve`.
Expected duration: 2–4 minutes. Verify with:

```
curl https://<api-id>.execute-api.ca-central-1.amazonaws.com/v1/routes/63
```

## Destroy

```
make destroy
```

Runs `terraform destroy -auto-approve`. All resources are removed except S3 objects (lifecycle-managed).

---

## Alarms and Response

### ingestor-error-rate
Ingestor Lambda failed for 2 consecutive minutes. CTRS scores are stale.

1. Check logs: CloudWatch → `/aws/lambda/halifax-transit-ingestor`
2. Common causes: GTFS feed unreachable, DynamoDB PutItem denied
3. If GTFS feed down: wait — feed outages are typically <5 min
4. If IAM error: verify ingestor role has `dynamodb:PutItem` on `TransitScores`

### api-error-rate
API Lambda returning 5xx errors.

1. Check logs: CloudWatch → `/aws/lambda/halifax-transit-api`
2. Common cause: DynamoDB Query timeout, cold start spike after deployment
3. Force warm-up: invoke the Lambda once manually via console

### api-p95-latency
p95 response time exceeded 200ms.

1. Check if cache is enabled: API Gateway → Stages → v1 → cache cluster = Active
2. If cache cluster stopped: re-enable via console or `make deploy`
3. If cache is fine: likely cold start spike — resolves within 60s

### dynamodb-throttled-requests
DynamoDB throttling on PAY_PER_REQUEST — should never fire under normal load.

1. Check write volume: may indicate ingestor is looping / double-triggering
2. Check EventBridge rule: verify rate is `rate(1 minute)`, not higher
3. If persistent: open AWS Support ticket — PAY_PER_REQUEST throttling indicates a service-side issue

### streams-error-rate
S3 archival Lambda failing — live scores are unaffected, but time-series data lake is falling behind.

1. Check logs: CloudWatch → `/aws/lambda/halifax-transit-streams`
2. Common cause: S3 bucket permissions, TypeDeserializer error on unexpected DynamoDB schema
3. DynamoDB Streams retains records for 24h — archival will catch up once fixed

---

## Rollback

Terraform manages all infrastructure as code. To roll back to a previous Lambda version:

```
# List published versions
aws lambda list-versions-by-function --function-name halifax-transit-api

# Point alias to previous version
aws lambda update-alias \
  --function-name halifax-transit-api \
  --name live \
  --function-version <previous-version>
```

No Terraform apply needed — alias update is immediate.

---

## Useful Commands

```bash
# Tail ingestor logs (last 5 min)
aws logs tail /aws/lambda/halifax-transit-ingestor --since 5m

# Tail API logs
aws logs tail /aws/lambda/halifax-transit-api --since 5m

# Check DynamoDB item count
aws dynamodb scan --table-name TransitScores --select COUNT

# List S3 archived files (today)
aws s3 ls s3://halifax-transit-scores-143320676328/scores/year=2026/ --recursive | head -20
```

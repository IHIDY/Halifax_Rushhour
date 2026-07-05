# Halifax Transit Real-Time Delay Analytics Pipeline

Serverless CQRS pipeline on AWS that ingests Halifax Transit GTFS-Realtime feeds every minute, computes a Composite Transit Reliability Score (CTRS) per route, and exposes results via a cached REST API.

## Architecture

```
EventBridge (1/min)
       ↓
Ingestor Lambda → DynamoDB (TransitScores)
                       ↓ Streams
                  Streams Lambda → S3 Data Lake (permanent archive)

User → API Gateway (15s cache) → API Lambda → DynamoDB
```

**Stack:** Python 3.12 · AWS Lambda · DynamoDB · API Gateway · EventBridge · S3 · Terraform

## Prerequisites

- AWS CLI configured with credentials for `ca-central-1`
- Terraform >= 1.5
- Python 3 + pip (conda or venv)
- GNU Make

## Deploy

```bash
make deploy
```

Installs Lambda dependencies, packages zips, and runs `terraform apply`. Takes ~3 minutes on first run.

## Destroy

```bash
make destroy
```

## API

```
GET /v1/routes/{route_id}
GET /v1/health
```

Active routes: 61, 62, 63, 65, 67, 68, 6B, 6C, 72, 7A, 7B, 8, 82, 83, 84, 85, 86, 87, 88, 90, 91, 9A, 9B

Example:
```bash
curl https://<api-id>.execute-api.ca-central-1.amazonaws.com/v1/routes/63
```

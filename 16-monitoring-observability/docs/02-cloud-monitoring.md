# 2. Cloud Monitoring

## What Is It? (Plain English)

Cloud Monitoring is where GCP automatically shows you how a deployed service is behaving — how many requests it's getting, how long they take, how much memory it's using — without you writing a single line of extra code.

## Why It Matters for AI Engineers

Before you ever define a custom metric (topic 5), Cloud Monitoring already gives you the basics for free the moment something is deployed on Cloud Run. This topic is about knowing what's already there before reaching for anything custom.

## Key Concepts

| Term | Meaning |
|------|---------|
| **Built-in Metric** | Something GCP collects automatically for supported resource types — no code needed |
| **Resource Type** | What's being measured — `cloud_run_revision`, in this module's case |
| **Time Series** | A metric's values over time — what every graph in Monitoring is actually showing |
| **Metrics Explorer** | The Console tool for browsing and charting any metric, built-in or custom |

## How It Fits Together

```mermaid
flowchart LR
    A["digest-worker-observable<br/>(Cloud Run)"] --> B["Request count"]
    A --> C["Request latency"]
    A --> D["Memory / CPU usage"]
    B --> E["Metrics Explorer"]
    C --> E
    D --> E
```

## Step-by-Step

**1. Generate some traffic** (a few normal calls, if you haven't already):
```bat
curl %SERVICE_URL%
curl %SERVICE_URL%
curl %SERVICE_URL%
```

**2. Open Metrics Explorer:** Console → **Monitoring → Metrics Explorer** → select resource type `Cloud Run Revision`, metric `Request Count` (or `Request Latencies`).

**3. From the CLI, list what's available.** `gcloud monitoring metrics-descriptors list` does not exist in current gcloud SDK versions (confirmed — no such subcommand anywhere under `gcloud monitoring`, `gcloud alpha monitoring`, or `gcloud beta monitoring`). Call the underlying Monitoring REST API directly instead — the CLI is just a thin wrapper around this same API:
```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://monitoring.googleapis.com/v3/projects/%PROJECT_ID%/metricDescriptors?filter=metric.type%3Dstarts_with(%22run.googleapis.com%22)&pageSize=10"
```

## Common Pitfalls

- Assuming you need to set anything up for these — built-in metrics for supported resources (Cloud Run, Cloud Functions, etc.) are automatic.
- Confusing this topic with topic 5 — this is what GCP gives you; topic 5 is what you define yourself.
- Looking for data before any traffic has happened — an idle service with zero requests has nothing to graph yet.
- Reaching for `gcloud monitoring metrics-descriptors list` — it doesn't exist in current gcloud versions; use the REST API directly (step 3) or just browse Metrics Explorer in the Console instead.

## Quick Recap

1. What has to happen before Cloud Monitoring shows anything for this service?
2. Name two built-in metrics available for a Cloud Run service with zero extra code.
3. What's the difference between this topic and topic 5?

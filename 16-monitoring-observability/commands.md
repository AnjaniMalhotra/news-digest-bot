# Module 16 — Monitoring & Observability — commands.md

Real, literal commands run on this machine (macOS), in the order they were
run, against GCP project `gcp-fde-project` (same project as Modules 14/15).
The original `.bat` files (which hardcode `PROJECT_ID=agentic-ai-capstone-1`,
not accessible from this account) live in `bat-files/` for reference —
every command below was actually executed with the real values shown.

Two bugs found for real in Modules 14/15 were fixed **upfront** here
instead of being rediscovered: the Google News `/rss/search` URL being
blocked from GCP egress IPs (swapped for a TechCrunch feed in `main.py`
and 2 docs), and the missing `roles/aiplatform.user` grant on the worker's
service account (added to `bat-files/00a_initial_setup.bat`).

## 0. One-time project setup

```bash
gcloud config list
# project = gcp-fde-project (already set from Modules 14/15)

gcloud services enable clouderrorreporting.googleapis.com --project=gcp-fde-project
# only new API needed - run, logging, monitoring, cloudtrace,
# secretmanager, cloudbuild all already enabled
```

No local venv needed - `requirements.txt` at the module root confirms
everything runs inside the Cloud Run build itself (same as Module 14).

Repo-level `.gitignore` created fresh on this branch (independent git
history). Original `.bat` files moved into `bat-files/`. `.env` created
with real values - same `gcp-fde-project`, same Telegram bot/chat ID
reused again, new Secret Manager name `telegram-bot-token-observability`,
real notification email for topic 6's alert.

## 0a. Service account, IAM, secret (one-time)

```bash
gcloud iam service-accounts create digest-observable-sa \
  --display-name="Digest Worker Observable Runtime SA" --project=gcp-fde-project

for role in logging.logWriter cloudtrace.agent monitoring.metricWriter aiplatform.user; do
  gcloud projects add-iam-policy-binding gcp-fde-project \
    --member="serviceAccount:digest-observable-sa@gcp-fde-project.iam.gserviceaccount.com" \
    --role="roles/$role" --condition=None
done
```

The very first grant (`logging.logWriter`) failed with `Service account
... does not exist` — ordinary IAM propagation lag immediately after
creating a new SA, not a real bug. Retried a few seconds later and it
succeeded; the other three roles (granted in the same loop, slightly
later) worked on the first try.

```bash
gcloud secrets create telegram-bot-token-observability --replication-policy=automatic --project=gcp-fde-project
set -a && source .env && set +a
printf '%s' "$TELEGRAM_BOT_TOKEN" | gcloud secrets versions add telegram-bot-token-observability --data-file=- --project=gcp-fde-project

gcloud secrets add-iam-policy-binding telegram-bot-token-observability \
  --member="serviceAccount:digest-observable-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" --project=gcp-fde-project
```

This worker SA now has all four roles it needs from the start
(`logWriter`, `cloudtrace.agent`, `metricWriter`, `aiplatform.user`, plus
`secretAccessor` on its own secret) — the pre-emptive `aiplatform.user`
fix from Modules 14/15 baked in here too.

## 1. Cloud Logging (deploy + view logs)

```bash
cd 16-monitoring-observability
gcloud run deploy digest-worker-observable \
  --source=digest_worker_observable \
  --region=us-central1 \
  --allow-unauthenticated \
  --service-account=digest-observable-sa@gcp-fde-project.iam.gserviceaccount.com \
  --set-env-vars=PROJECT_ID=gcp-fde-project,LOCATION=us-central1,TELEGRAM_CHAT_ID=8966022242,SECRET_NAME=telegram-bot-token-observability \
  --project=gcp-fde-project
# Service URL: https://digest-worker-observable-1039893753206.us-central1.run.app
```

(This is a source-based `gcloud run deploy`, so Cloud Build runs
server-side — no local Docker/arm64 concerns like Module 14's manual
`docker build` + `docker push` flow.)

`.env`'s `SERVICE_URL` updated to the printed URL.

```bash
curl https://digest-worker-observable-1039893753206.us-central1.run.app
```

**Real bug hit — in the module's own application code, not IAM/config.**
Got a bare `500 Internal Server Error`. Read the actual traceback rather
than guessing:

```bash
gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=digest-worker-observable AND textPayload:"Traceback"' --project=gcp-fde-project --limit=5
```

```
File "/app/main.py", line 71, in write_custom_metric
  point.interval.end_time.seconds = int(now)
AttributeError: 'NoneType' object has no attribute 'seconds'
```

Root cause: `monitoring_v3.Point()`'s `interval` submessage auto-vivifies
fine, but `end_time` is a well-known `Timestamp` field, which the client
library does *not* let you mutate field-by-field in place the way a plain
submessage works — it must be constructed and assigned as a whole. This
crashed on *every* successful run (it's called unconditionally after a
successful summarize+send), not just topic 5 — so it blocked this very
first deploy's basic test, before custom metrics were even the topic.
Fixed properly using the client library's documented construction
pattern, in `digest_worker_observable/main.py`:

```python
seconds = int(now)
nanos = int((now - seconds) * 10**9)
interval = monitoring_v3.TimeInterval({"end_time": {"seconds": seconds, "nanos": nanos}})
point = monitoring_v3.Point({"interval": interval, "value": {"int64_value": headline_count}})
```

Redeployed, retested:

```json
{"headline_count": 10, "status": "sent", "summary": "..."}
```

Independently verified via Telegram `message_id` (advanced past the prior
baseline from Module 15, confirming real delivery — note: the *first*,
crashing test had already sent its Telegram message successfully before
failing later at the metric-write step, since `send_to_telegram` runs
before `write_custom_metric` in the code; a small, expected off-by-one in
the message count, not a concern).

Structured log view (topic 1's actual teaching point):

```bash
gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=digest-worker-observable' --project=gcp-fde-project --limit=20 --format=json
```

Confirms the `logging.info(..., extra={"json_fields": {...}})` calls in
`main.py` produce real structured `jsonPayload` entries (`feed_url`,
`simulate_error`, `simulate_slow`, etc.), not just plain text — queryable
by field in Logs Explorer.

## 2. Cloud Monitoring

```bash
for i in 1 2 3; do curl -s -o /dev/null -w "status=%{http_code}\n" https://digest-worker-observable-1039893753206.us-central1.run.app; done
```

**Real bug hit — a stale gcloud command in the module's own script.**
`bat-files/02_view_monitoring.bat` runs `gcloud monitoring
metrics-descriptors list`, which doesn't exist in this gcloud SDK version
(`Invalid choice: 'metrics-descriptors'`). Confirmed via `gcloud monitoring
--help` and `gcloud alpha/beta monitoring --help` — no subcommand for
listing metric descriptors exists anywhere in the current CLI tree. Not
something to work around by skipping the check; used the underlying
Monitoring REST API directly instead (the CLI is just a thin wrapper
around this same API):

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://monitoring.googleapis.com/v3/projects/gcp-fde-project/metricDescriptors?filter=metric.type%3D%22run.googleapis.com%2Frequest_count%22"
```

Confirms `run.googleapis.com/request_count` (and the other Cloud Run
metrics topic 7's dashboard uses) exist and are automatically collected —
no application code involved, exactly this topic's teaching point.
Console: **Monitoring → Metrics Explorer**, resource type "Cloud Run
Revision", chart "Request Count" or "Request Latencies".

## 3. Error Reporting

```bash
curl "https://digest-worker-observable-1039893753206.us-central1.run.app/?simulate_error=true"
# 500 Internal Server Error (expected, on purpose)
```

Checked ERROR-severity logs — the first query happened to return a
*cached* result from an earlier, different crash (topic 1's pre-fix
`AttributeError`, timestamped well before this test). Compared timestamps
explicitly rather than assuming the first result was current:

```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=digest-worker-observable' --project=gcp-fde-project --limit=20 --format="value(timestamp,severity,textPayload)"
```

Found the real, current entry, matching exactly what this topic expects:

```
RuntimeError: Simulated failure - this is intentional, see topic 3
```

Checking Error Reporting's own view: `gcloud error-reporting` doesn't
exist in this gcloud installation, and `gcloud beta error-reporting`
requires installing the beta component interactively. Used the REST API
directly instead (same approach as topic 2's fix):

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://clouderrorreporting.googleapis.com/v1beta1/projects/gcp-fde-project/groupStats?timeRange.period=PERIOD_1_DAY&serviceFilter.service=digest-worker-observable"
```

Confirmed **two separate, auto-grouped error groups** for
`digest-worker-observable` — the earlier real `AttributeError` bug from
topic 1 and this simulated `RuntimeError` — each with its own real Python
stack trace, exactly this topic's point: distinct errors get grouped
separately, not lumped together. Console: **Error Reporting**, same view.

## 4. Cloud Trace

```bash
curl "https://digest-worker-observable-1039893753206.us-central1.run.app/?simulate_slow=true"
curl "https://digest-worker-observable-1039893753206.us-central1.run.app"
```

Wall-clock `time` on the two `curl` calls wasn't a clean comparison — both
came back in the 25-27s range, muddied by Cloud Run cold-start variance
(the instance had scaled down between topics). Didn't trust that noisy
signal; went straight to the actual trace data instead, which is this
topic's real point anyway:

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://cloudtrace.googleapis.com/v1/projects/gcp-fde-project/traces?view=COMPLETE&pageSize=10&filter=%2Broot%3Arun_digest"
```

(Trace ingestion took about 30-40s to show up — not instant, worth noting
so it doesn't look broken if checked too early.)

Computed each `summarize_headlines` span's real duration from
`startTime`/`endTime`, and cross-checked against the span's own
`simulated_slowness` attribute (set explicitly in `main.py` via
`span.set_attribute`) rather than guessing from duration alone:

```
trace 096da1677ee6 | simulated_slowness=true  | duration=25.90s
trace 0afd7318ebca | simulated_slowness=false | duration=10.61s
trace 10a7a22d0f1f | simulated_slowness=false | duration=12.49s
trace 11f8ef77ec10 | simulated_slowness=false | duration=12.52s
trace 626a608e3a02 | simulated_slowness=false | duration=10.13s
trace 630ca895d068 | simulated_slowness=false | duration=9.83s
trace 92ee1955227b | simulated_slowness=false | duration=15.07s
trace 9d35077aa475 | simulated_slowness=false | duration=6.92s
```

The one trace explicitly flagged `simulated_slowness=true` is also the
clear outlier (25.9s vs a 6.9-15.1s spread for every normal run) —
confirms the deliberate `time.sleep(8)` genuinely dominates that specific
span's waterfall, exactly this topic's claim, verified by the span's own
attribute rather than assumed from timing alone. Console: **Trace → Trace
List**, open the recent traces and compare the `summarize_headlines` span
width directly.

## 5. Custom Metrics

```bash
curl https://digest-worker-observable-1039893753206.us-central1.run.app > /dev/null
```

**Same stale-command issue as topic 2, in a different subcommand.**
`gcloud monitoring time-series list` also doesn't exist in this gcloud SDK
version (`Invalid choice: 'time-series'`). Used the Monitoring REST API's
`timeSeries.list` directly instead:

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://monitoring.googleapis.com/v3/projects/gcp-fde-project/timeSeries?filter=metric.type%3D%22custom.googleapis.com%2Fdigest%2Fheadlines_processed%22&interval.startTime=<10 min ago>&interval.endTime=<now>"
```

Real result: 9 data points, all `int64Value: 10` — matches the feed's
actual headline count on every successful run since the topic-1 fix
(`headline_count` from each `run_digest` response). Confirms the custom
metric is real, being written by the app's own code
(`custom.googleapis.com/digest/headlines_processed`), and is genuinely
absent from topic 2's built-in metric list — exactly this topic's point.
Console: **Monitoring → Metrics Explorer**, search "headlines_processed".

## 6. Alerts

```bash
gcloud logging metrics create digest_simulated_errors \
  --description="Counts simulated digest-worker errors" \
  --log-filter='resource.type=cloud_run_revision AND jsonPayload.message="simulated failure triggered on purpose"' \
  --project=gcp-fde-project
```

**Real bug hit before even running anything — caught by checking the
actual log format first, not by trial and error.** The module's own
`.bat` filter is `textPayload:"simulated failure triggered on purpose"`.
Checked what topic 3's `logging.error(...)` call actually produces (this
service calls `cloud_logging.Client().setup_logging()`, which routes
Python's `logging` module through *structured* Cloud Logging):

```bash
gcloud logging read '... AND (textPayload:"simulated failure" OR jsonPayload.message:"simulated failure")' --project=gcp-fde-project --limit=5 --format=json
```

Confirmed: the traceback (an unhandled exception's stderr dump) really is
`textPayload`, but the deliberate `logging.error("simulated failure
triggered on purpose", extra={"json_fields": {...}})` call is
`jsonPayload.message` — a completely different field. The documented
filter would have matched *zero* real log entries, so the log-based
metric would sit at zero forever and the alert would never fire, silently,
with no error anywhere to point at the problem. Fixed by using
`jsonPayload.message="..."` instead, verified before creating the alert
around it.

```bash
gcloud alpha monitoring channels create \
  --display-name="My Email" --type=email \
  --channel-labels=email_address=anjanimalhotra09@gmail.com \
  --project=gcp-fde-project
# projects/gcp-fde-project/notificationChannels/14037811656753183705
```

`06_alert_policy.json`'s `NOTIFICATION_CHANNEL_ID_HERE` replaced with the
real channel name above.

```bash
gcloud alpha monitoring policies create --policy-from-file=06_alert_policy.json --project=gcp-fde-project
# projects/gcp-fde-project/alertPolicies/11398678677717922077

curl "https://digest-worker-observable-1039893753206.us-central1.run.app/?simulate_error=true"
curl "https://digest-worker-observable-1039893753206.us-central1.run.app/?simulate_error=true"
```

Verified the fixed log-based metric actually counted these, rather than
just trusting the policy exists:

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://monitoring.googleapis.com/v3/projects/gcp-fde-project/timeSeries?filter=metric.type%3D%22logging.googleapis.com%2Fuser%2Fdigest_simulated_errors%22&interval.startTime=<15 min ago>&interval.endTime=<now>"
```

Real result: `int64Value: 2` for the exact one-minute window both curl
calls landed in — matches precisely. Confirmed the alert policy is
enabled and its condition (`count > 0`) is genuinely satisfied by this
real data. Did not confirm actual email delivery — Google's own docs
note evaluation and notification both take real time beyond this
session's testing window, and there's no way to check an inbox
programmatically from here.

## 7. Dashboards

```bash
gcloud monitoring dashboards create --config-from-file=07_dashboard.json --project=gcp-fde-project
# Created [e273cfa4-6df2-4f7c-a760-c108478e04c0]

curl https://digest-worker-observable-1039893753206.us-central1.run.app -o /dev/null
curl "https://digest-worker-observable-1039893753206.us-central1.run.app/?simulate_error=true" -o /dev/null
curl "https://digest-worker-observable-1039893753206.us-central1.run.app/?simulate_slow=true" -o /dev/null

gcloud monitoring dashboards list --project=gcp-fde-project --format="value(name,displayName)"
# projects/1039893753206/dashboards/e273cfa4-6df2-4f7c-a760-c108478e04c0   Digest Worker Health
```

No bugs this time — the dashboard's own JSON needed no changes. Verified
each of its 4 tiles has real underlying data (not just that the dashboard
object exists) by querying each metric directly:

- Request Count (`run.googleapis.com/request_count`) — confirmed in topic 2
- Simulated Error Count (`logging.googleapis.com/user/digest_simulated_errors`) — confirmed in topic 6
- Headlines Processed (`custom.googleapis.com/digest/headlines_processed`) — confirmed in topic 5
- Request Latency p95 (`run.googleapis.com/request_latencies`) — checked here directly:

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://monitoring.googleapis.com/v3/projects/gcp-fde-project/timeSeries?filter=metric.type%3D%22run.googleapis.com%2Frequest_latencies%22...&interval.startTime=<15 min ago>&interval.endTime=<now>"
# timeSeries count: 4
```

Console: **Monitoring → Dashboards → "Digest Worker Health"**.

## Final cleanup

_Pending — run when the module is fully demoed and verified._

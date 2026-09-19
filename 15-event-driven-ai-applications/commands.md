# Module 15 — Event-Driven AI Applications — commands.md

Real, literal commands run on this machine (macOS), in the order they were
run, against GCP project `gcp-fde-project` (same project as Module 14 —
this module is treated as an enhancement layered on top of it, per the
module's own note that it "directly continues Module 14"). The original
`.bat` files (which hardcode `PROJECT_ID=agentic-ai-capstone-1`, not
accessible from this account) live in `bat-files/` for reference — every
command below was actually executed with the real values shown.

Two bugs found for real in Module 14 were fixed **upfront** here instead of
being rediscovered: the Google News `/rss/search` URL being blocked from
GCP egress IPs (swapped for a TechCrunch feed in `main.py`,
`04_create_tasks.py`, the three affected `.bat` files, and 3 docs), and the
missing `roles/aiplatform.user` grant on the worker's service account
(added to `bat-files/00a_initial_setup.bat`).

## 0. One-time project setup

```bash
gcloud config list
# [core] account = mentordivesh@gmail.com, project = gcp-fde-project
# (already set from Module 14 - same project, no change needed)

gcloud services enable eventarc.googleapis.com cloudscheduler.googleapis.com \
  cloudtasks.googleapis.com apigateway.googleapis.com servicecontrol.googleapis.com \
  --project=gcp-fde-project
# Operation "operations/acf.p2-1039893753206-cbc016f2-..." finished successfully.
# (run.googleapis.com, cloudfunctions.googleapis.com, pubsub.googleapis.com,
# storage.googleapis.com were already enabled from Module 14)

cd 15-event-driven-ai-applications
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
# installs python-dotenv + google-cloud-tasks, needed to run
# 04_create_tasks.py from this host machine (unlike Module 14, which needed
# no local venv at all)
```

Repo-level `.gitignore` created fresh on this branch (independent git
history from the Module 14 branch, so it didn't carry over).

Original `.bat` files moved into `bat-files/` (`git mv`, kept for
reference, not deleted).

`.env` created with real values — same `gcp-fde-project`, same Telegram
bot/chat ID reused from Module 14 (the module's own docs say either
works), new Secret Manager name `telegram-bot-token-eventdriven` (no
collision with Module 14's `telegram-bot-token`).

## 0a. Service accounts, secret, and IAM (one-time)

```bash
gcloud iam service-accounts create digest-worker-sa \
  --display-name="Digest Worker Runtime SA" --project=gcp-fde-project
gcloud iam service-accounts create digest-tasks-sa \
  --display-name="Digest Tasks Dispatcher SA" --project=gcp-fde-project

gcloud secrets create telegram-bot-token-eventdriven --replication-policy=automatic --project=gcp-fde-project
set -a && source .env && set +a
printf '%s' "$TELEGRAM_BOT_TOKEN" | gcloud secrets versions add telegram-bot-token-eventdriven --data-file=- --project=gcp-fde-project
# Created version [1]

gcloud secrets add-iam-policy-binding telegram-bot-token-eventdriven \
  --member="serviceAccount:digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" --project=gcp-fde-project

gcloud projects add-iam-policy-binding gcp-fde-project \
  --member="serviceAccount:digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user" --condition=None --project=gcp-fde-project
```

This is the pre-emptive fix from Module 14 baked in upfront — the worker
SA now has exactly the two roles it needs (`secretAccessor` +
`aiplatform.user`) before any function is even deployed, so no
"permission denied on Gemini" failure should occur the first time each
worker variant is tested below.

## 1. Pub/Sub

```bash
gcloud pubsub topics create digest-requests --project=gcp-fde-project

cd 15-event-driven-ai-applications
gcloud functions deploy digest-worker-pubsub \
  --gen2 --runtime=python311 --region=us-central1 --source=digest_worker \
  --entry-point=on_pubsub_message \
  --trigger-topic=digest-requests \
  --service-account=digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com \
  --set-env-vars=PROJECT_ID=gcp-fde-project,LOCATION=us-central1,TELEGRAM_CHAT_ID=8966022242,SECRET_NAME=telegram-bot-token-eventdriven \
  --project=gcp-fde-project

gcloud pubsub topics publish digest-requests \
  --message='{"feed_url": "https://techcrunch.com/tag/artificial-intelligence/feed/"}' \
  --project=gcp-fde-project
```

**Real bug hit, not in Module 14 (new trigger type, new failure mode):**
nothing arrived in Telegram. `gcloud functions logs read digest-worker-pubsub`
showed repeated:

```
WARNING  The request was not authenticated. ... The IAM principal lacks
{run.routes.invoke} permission.
```

Root-caused rather than guessed — found the actual auto-created push
subscription and the identity it authenticates as:

```bash
gcloud pubsub subscriptions list --project=gcp-fde-project \
  --format="table(name,pushConfig.pushEndpoint,pushConfig.oidcToken.serviceAccountEmail)"
# eventarc-us-central1-digest-worker-pubsub-305955-sub-990 ...
# serviceAccountEmail: digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com
```

A gen2 Pub/Sub-triggered function is delivered via an auto-created Eventarc
push subscription that (with no separate trigger SA specified) authenticates
as the function's own runtime service account — meaning
`digest-worker-sa` needs `roles/run.invoker` **on itself** (on the Cloud
Run service Eventarc actually deploys under the hood), which it didn't
have. Fixed:

```bash
gcloud run services add-iam-policy-binding digest-worker-pubsub \
  --region=us-central1 \
  --member="serviceAccount:digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/run.invoker" \
  --project=gcp-fde-project
```

Re-published the same test message. Result, from the function's own logs
(`gcloud functions logs read digest-worker-pubsub`):

```
{'status': 'sent', 'summary': "Here's a quick look at today's top tech and AI news:...", 'telegram_status': 200}
```

Independently verified (not just trusting the log line) by sending a
second, direct Telegram message via the bot API and confirming the
`message_id` sequence incremented past the digest's own send.

**Baked in for future runs:** the `run.invoker` self-grant is now step 3
of `bat-files/01_pubsub_setup.bat` and `docs/01-pub-sub.md` itself, so a
future run of this module won't rediscover it from scratch. Worth watching
for in topic 3 (Cloud Scheduler) too, since it reuses this same function
and topic — if it's already granted here, topic 3 needs no new grant.

## 2. Eventarc

```bash
gcloud storage buckets create gs://digest-feeds-bucket-gcp-fde-project --location=us-central1 --project=gcp-fde-project
# name was available on first try - no collision

gcloud functions deploy digest-worker-storage \
  --gen2 --runtime=python311 --region=us-central1 --source=digest_worker \
  --entry-point=on_storage_event \
  --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
  --trigger-event-filters="bucket=digest-feeds-bucket-gcp-fde-project" \
  --service-account=digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com \
  --set-env-vars=PROJECT_ID=gcp-fde-project,LOCATION=us-central1,TELEGRAM_CHAT_ID=8966022242,SECRET_NAME=telegram-bot-token-eventdriven \
  --project=gcp-fde-project
```

**Real bug #1:** deploy itself failed —
`Permission 'eventarc.events.receiveEvent' denied`. `digest-worker-sa` needs
`roles/eventarc.eventReceiver` on the project *before* the trigger can be
created at all (this wasn't required for topic 1's `--trigger-topic`
Pub/Sub trigger — only for a direct `--trigger-event-filters` Eventarc
trigger):

```bash
gcloud projects add-iam-policy-binding gcp-fde-project \
  --member="serviceAccount:digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/eventarc.eventReceiver" --condition=None
```

**Real bug #2:** retried the deploy — failed differently, at the trigger
creation step: `Failed to update storage bucket metadata. Possible causes
include: Cloud Storage service agent not being able to read the Cloud
Pub/Sub topic ... created by Eventarc`. Found the actual GCS service agent
and granted it publish access (a one-time, per-project prerequisite for
*any* GCS-to-Eventarc trigger, not specific to this bucket):

```bash
gcloud storage service-agent --project=gcp-fde-project
# service-1039893753206@gs-project-accounts.iam.gserviceaccount.com

gcloud projects add-iam-policy-binding gcp-fde-project \
  --member="serviceAccount:service-1039893753206@gs-project-accounts.iam.gserviceaccount.com" \
  --role="roles/pubsub.publisher" --condition=None
```

Deploy succeeded on the third attempt. Proactively granted `run.invoker`
on `digest-worker-storage` to itself before testing (same lesson as
topic 1 — a different Cloud Run service, so a separate binding was still
needed):

```bash
gcloud run services add-iam-policy-binding digest-worker-storage \
  --region=us-central1 \
  --member="serviceAccount:digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/run.invoker" --project=gcp-fde-project

echo "https://techcrunch.com/tag/artificial-intelligence/feed/" > /tmp/feeds.txt
gcloud storage cp /tmp/feeds.txt gs://digest-feeds-bucket-gcp-fde-project/feeds.txt --project=gcp-fde-project
```

**Real bug #3:** the function now ran (no more auth warnings), but crashed
inside its own code — `gcloud functions logs read digest-worker-storage`
showed a real Python traceback:

```
google.api_core.exceptions.Forbidden: 403 GET .../feeds.txt?alt=media:
digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com does not have
storage.objects.get access
```

Receiving the event notification and reading the file it points to are two
separate permissions. Fixed:

```bash
gcloud storage buckets add-iam-policy-binding gs://digest-feeds-bucket-gcp-fde-project \
  --member="serviceAccount:digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer" --project=gcp-fde-project

gcloud storage cp /tmp/feeds.txt gs://digest-feeds-bucket-gcp-fde-project/feeds.txt --project=gcp-fde-project
```

Result, from `gcloud functions logs read digest-worker-storage`:

```
{'status': 'sent', 'summary': "Here's a quick look at today's top tech news:...", 'telegram_status': 200}
```

Independently verified the same way as topic 1 — a direct Telegram
`sendMessage` call confirmed the `message_id` sequence had advanced past
the digest's own send.

**Baked in for future runs:** all three fixes (eventReceiver before deploy,
GCS service agent's pubsub.publisher, and the bucket-level objectViewer
grant) plus the run.invoker self-grant are now steps 2, 3, 5, and 6 of
`bat-files/02_eventarc_setup.bat` and `docs/02-eventarc.md`, in the correct
order (eventReceiver *before* the deploy — doing it after, like the other
three, doesn't work since the deploy itself needs it).

## 3. Cloud Scheduler

```bash
gcloud scheduler jobs create pubsub morning-digest-job \
  --schedule="0 8 * * *" \
  --topic=digest-requests \
  --message-body='{"feed_url": "https://techcrunch.com/tag/artificial-intelligence/feed/"}' \
  --time-zone="Asia/Kolkata" \
  --location=us-central1 \
  --project=gcp-fde-project

gcloud scheduler jobs run morning-digest-job --location=us-central1 --project=gcp-fde-project
```

No new IAM needed — reuses topic 1's `digest-requests` topic and
`digest-worker-pubsub`, which already has its `run.invoker` self-grant
from topic 1.

**Not a bug, but a real timing gotcha worth recording:** the first
`gcloud logging read` check (run immediately after `jobs run`) came back
empty, which looked like a silent failure. Root-caused rather than
assumed broken:
- `gcloud scheduler jobs describe morning-digest-job --format=json` showed
  `"status": {}` (empty = success; Cloud Scheduler only populates `status`
  with error details on a *failed* attempt) and a real `lastAttemptTime`.
- A log query run a few seconds later showed the function actually
  starting and mid-flight (the Gemini AFC advisory line), just not
  finished yet — Cloud Logging ingestion has a short delay, not an error.

Independently verified via the Telegram `message_id` sequence: the ping
sent for this topic came back as `message_id: 13`, with `11` being the
prior (topic 2) ping — confirming message `12` was sent in between, i.e.
the scheduler-triggered digest really was delivered.

## 4. Cloud Tasks

```bash
gcloud tasks queues create digest-fetch-queue --location=us-central1 --project=gcp-fde-project

cd 15-event-driven-ai-applications
gcloud functions deploy digest-worker-http \
  --gen2 --runtime=python311 --region=us-central1 --source=digest_worker \
  --entry-point=on_http_request \
  --trigger-http --no-allow-unauthenticated \
  --service-account=digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com \
  --set-env-vars=PROJECT_ID=gcp-fde-project,LOCATION=us-central1,TELEGRAM_CHAT_ID=8966022242,SECRET_NAME=telegram-bot-token-eventdriven \
  --project=gcp-fde-project
# uri: https://digest-worker-http-mewtpyvzkq-uc.a.run.app

gcloud run services add-iam-policy-binding digest-worker-http \
  --region=us-central1 \
  --member="serviceAccount:digest-tasks-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/run.invoker" --project=gcp-fde-project

# .env's WORKER_HTTP_URL updated to the printed uri
./.venv/bin/python 04_create_tasks.py
# 3 tasks created
```

**Real bug hit — the documented `run.invoker` grant alone was not enough.**
All 3 tasks failed repeatedly:

```bash
gcloud tasks list --queue=digest-fetch-queue --location=us-central1 --project=gcp-fde-project
# LAST_ATTEMPT_STATUS: PERMISSION_DENIED(7): HTTP status code 403
gcloud functions logs read digest-worker-http --region=us-central1 --gen2 --project=gcp-fde-project --limit=30
# WARNING The request was not authenticated. ... IAM principal lacks {run.routes.invoke} permission.
```

Root-caused rather than re-granting the same binding: confirmed the
`run.invoker` binding really was present and correct
(`gcloud run services get-iam-policy digest-worker-http`), then checked
whether anything had ever granted permission to actually *create* a token
as `digest-tasks-sa` in the first place:

```bash
gcloud iam service-accounts get-iam-policy digest-tasks-sa@gcp-fde-project.iam.gserviceaccount.com
# empty - nothing granted
```

Cloud Tasks' own service agent needs `roles/iam.serviceAccountTokenCreator`
on the dispatcher SA to mint its OIDC token at all — without it, Cloud
Tasks can't produce a valid token, so every request arrives at Cloud Run
unauthenticated, producing the *exact same* error message as a missing
`run.invoker` grant. Easy to misdiagnose as "the invoker grant didn't
take." Fixed:

```bash
gcloud projects describe gcp-fde-project --format="value(projectNumber)"
# 1039893753206

gcloud iam service-accounts add-iam-policy-binding digest-tasks-sa@gcp-fde-project.iam.gserviceaccount.com \
  --member="serviceAccount:service-1039893753206@gcp-sa-cloudtasks.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator" --project=gcp-fde-project

./.venv/bin/python 04_create_tasks.py
# 3 more tasks created
```

Result: `gcloud tasks list --queue=digest-fetch-queue ...` came back
`Listed 0 items` — every task (the original 3, which Cloud Tasks had kept
retrying, plus the 3 new ones) succeeded and was removed from the queue.
Independently verified via the Telegram `message_id` sequence: the
pre-fix ping was `14`; the post-fix ping came back as `21` — exactly 6
digests landed in between, matching 3 retried + 3 fresh tasks. Also
confirmed with a direct authenticated call to `digest-worker-http`,
returning `{"status": "sent", ..., "telegram_status": 200}` in the raw
HTTP response (this entry point returns its result as the HTTP body
rather than printing to logs, unlike the pubsub/storage entry points —
not a bug, just why `gcloud functions logs read` shows no `'status'` line
for this one).

**Baked in for future runs:** the `serviceAccountTokenCreator` grant is now
step 4 of `bat-files/04_cloud_tasks_setup.bat` and `docs/04-cloud-tasks.md`,
directly after the `run.invoker` grant, with an explicit note that both are
required and skipping either produces an identical error.

## 5. API Gateway

`05_openapi_spec.yaml` edited: `WORKER_HTTP_URL_HERE` replaced with the
real `https://digest-worker-http-mewtpyvzkq-uc.a.run.app`.

```bash
gcloud api-gateway apis create digest-api --project=gcp-fde-project

cd 15-event-driven-ai-applications
gcloud api-gateway api-configs create digest-config \
  --api=digest-api \
  --openapi-spec=05_openapi_spec.yaml \
  --backend-auth-service-account=digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com \
  --project=gcp-fde-project
# took several minutes - normal for API Gateway, not a hang

gcloud api-gateway gateways create digest-gateway \
  --api=digest-api --api-config=digest-config \
  --location=us-central1 --project=gcp-fde-project
# also took several minutes

gcloud services api-keys create --display-name="Digest API Key" --project=gcp-fde-project
# keyString: (real key, not written here - see .env if reused later)

gcloud api-gateway gateways describe digest-gateway --location=us-central1 --project=gcp-fde-project --format="value(defaultHostname)"
# digest-gateway-d9pxw392.uc.gateway.dev
```

Test:
```bash
curl "https://digest-gateway-d9pxw392.uc.gateway.dev/trigger-digest?key=<the real key>"
```

**Real bug #5:** `{"code": 403, "message": "digest-api has not been used in
project 1039893753206 before or it is disabled. Enable it..."}` — the API
Gateway auto-creates its own managed service
(`digest-api-1gh4ofxsrvtp7.apigateway.gcp-fde-project.cloud.goog`), which
isn't enabled by default even after the gateway itself deploys
successfully. Fixed:

```bash
gcloud api-gateway apis describe digest-api --project=gcp-fde-project --format="value(managedService)"
# digest-api-1gh4ofxsrvtp7.apigateway.gcp-fde-project.cloud.goog

gcloud services enable digest-api-1gh4ofxsrvtp7.apigateway.gcp-fde-project.cloud.goog --project=gcp-fde-project
```

**Real bug #6:** retested — different error this time, a raw
`403 Forbidden ... Your client does not have permission to get URL
/?key=...` — the exact generic page a browser gets hitting a locked-down
Cloud Run URL with no auth at all (recognized it from Module 14). This
meant the request reached Cloud Run but arrived unauthenticated, even
though `--backend-auth-service-account=digest-worker-sa@...` was set.
Root-caused: `--backend-auth-service-account` only *declares* which
identity API Gateway signs its backend calls as — it doesn't grant that
identity anything. `digest-worker-sa` had never been granted `run.invoker`
on `digest-worker-http` (only `digest-tasks-sa` had, from topic 4).
Confirmed via `gcloud run services get-iam-policy digest-worker-http`
before fixing. Fixed:

```bash
gcloud run services add-iam-policy-binding digest-worker-http \
  --region=us-central1 \
  --member="serviceAccount:digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/run.invoker" --project=gcp-fde-project
```

Retested with a short poll (IAM propagation, same pattern as every earlier
topic) — succeeded on the 6th attempt:
```json
{"status":"sent","summary":"Here's a quick look at today's top tech news:...","telegram_status":200}
```

Independently verified via Telegram `message_id`: pre-fix ping was `21`
(from topic 4), post-fix ping came back `24` — multiple digests landed in
the gap, consistent with the propagation-window attempts succeeding, not
just the log line's own claim.

**Baked in for future runs:** both fixes (enabling the managed service,
granting `run.invoker` to the backend-auth SA) are now steps 4 and 5 of
`bat-files/05_api_gateway_setup.bat` and `docs/05-api-gateway.md`.

## Final cleanup

Torn down on 2026-09-19, after Module 16 was also finished, using the real
commands below. Every resource this module created was deleted and then
confirmed gone with `list` commands (functions, Pub/Sub topics and
subscriptions, Eventarc triggers, buckets, Scheduler, Tasks, API Gateway,
API keys, secrets, service accounts, project IAM policy) — nothing of this
module's was left.

API Gateway has to come down in order — gateway, then config, then API —
and each step waits on the last (the gateway took several minutes, the
config seconds, the API about a minute). Run it in the background while
doing the rest:

```bash
gcloud api-gateway gateways delete digest-gateway --location=us-central1 --project=gcp-fde-project --quiet
gcloud api-gateway api-configs delete digest-config --api=digest-api --project=gcp-fde-project --quiet
gcloud api-gateway apis delete digest-api --project=gcp-fde-project --quiet
```

The API's auto-created managed service
(`digest-api-1gh4ofxsrvtp7.apigateway.gcp-fde-project.cloud.goog`, which
topic 5 had to enable by hand) disappeared on its own when the API was
deleted — no `gcloud services disable` needed; confirmed by listing enabled
services afterwards.

```bash
# the API key needs its full resource name, not its display name
gcloud services api-keys delete projects/1039893753206/locations/global/keys/65488106-661d-4437-8761-151e4907bd67 --project=gcp-fde-project --quiet

gcloud scheduler jobs delete morning-digest-job --location=us-central1 --project=gcp-fde-project --quiet
gcloud tasks queues delete digest-fetch-queue --location=us-central1 --project=gcp-fde-project --quiet

gcloud functions delete digest-worker-pubsub --gen2 --region=us-central1 --project=gcp-fde-project --quiet
gcloud functions delete digest-worker-storage --gen2 --region=us-central1 --project=gcp-fde-project --quiet
gcloud functions delete digest-worker-http --gen2 --region=us-central1 --project=gcp-fde-project --quiet

gcloud pubsub topics delete digest-requests --project=gcp-fde-project --quiet
gcloud storage rm -r gs://digest-feeds-bucket-gcp-fde-project --project=gcp-fde-project
gcloud secrets delete telegram-bot-token-eventdriven --project=gcp-fde-project --quiet
```

Deleting the three functions also removed their Eventarc triggers **and**
the helper Pub/Sub topic and subscriptions Eventarc had created for them
(`eventarc-us-central1-digest-worker-...`) — listed Pub/Sub and Eventarc
right afterwards to confirm nothing was left over, so no manual cleanup of
those was needed. The `run.invoker` grants lived on the functions'
Cloud Run services and the Cloud Tasks `serviceAccountTokenCreator` grant
lived on `digest-tasks-sa` itself, so both went away with those resources.

The project-level grants were removed **before** deleting the service
accounts, so no orphaned `deleted:serviceAccount:...` entries are left in the
project's IAM policy. Listed the policy first to confirm these eight (across
Modules 14-16) were exactly the ones we added and nothing else:

```bash
gcloud projects remove-iam-policy-binding gcp-fde-project \
  --member="serviceAccount:digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user" --condition=None --quiet
gcloud projects remove-iam-policy-binding gcp-fde-project \
  --member="serviceAccount:digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/eventarc.eventReceiver" --condition=None --quiet
# granted to Cloud Storage's own helper account in topic 2:
gcloud projects remove-iam-policy-binding gcp-fde-project \
  --member="serviceAccount:service-1039893753206@gs-project-accounts.iam.gserviceaccount.com" \
  --role="roles/pubsub.publisher" --condition=None --quiet

gcloud iam service-accounts delete digest-worker-sa@gcp-fde-project.iam.gserviceaccount.com --project=gcp-fde-project --quiet
gcloud iam service-accounts delete digest-tasks-sa@gcp-fde-project.iam.gserviceaccount.com --project=gcp-fde-project --quiet
```

The `gcf-*` helper repo and buckets that Cloud Functions builds create are
shared with Module 14's function, and were deleted along with it — see
Module 14's cleanup section.

**Gaps in the original `bat-files/99_cleanup.bat`** (left unchanged there):
it never deletes the API key that `05_api_gateway_setup.bat` creates, so a
live key would have been left behind, and it doesn't remove any of the
project-level grants above.

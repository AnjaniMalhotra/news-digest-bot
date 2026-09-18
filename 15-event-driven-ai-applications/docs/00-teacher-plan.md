# Teacher Plan — Module 15: Event-Driven AI Applications

**Total time:** 3 hrs (180 min) — includes a 30 min buffer.
**Format:** Mostly `.bat` deployment scripts + `gcloud`, one small shared Cloud Function (`digest_worker/main.py`) deployed three different ways across the module.

## Before you start recording/teaching

- [ ] Module 14 complete — don't re-explain Cloud Functions, IAM, or Secret Manager from scratch here, just reference them
- [ ] Telegram bot token + chat ID ready
- [ ] `.env` filled in, `00_setup_vars.bat` run
- [ ] Run through the whole module yourself once first — API Gateway (topic 5) in particular has more setup steps than anything else in this module

## Suggested pacing (180 min)

| # | Topic | Minutes | Format |
|---|-------|---------|--------|
| 1 | Pub/Sub | 35 | Deploy + publish a test message |
| 2 | Eventarc | 30 | Deploy + upload a file, watch it fire |
| 3 | Cloud Scheduler | 20 | Create the job, mention the Module 14 callback |
| 4 | Cloud Tasks | 30 | Create the queue, enqueue tasks for multiple feeds |
| 5 | API Gateway | 35 | Deploy config + gateway, get an API key, test with curl |
| — | Buffer | 30 | — |

## Teaching order rationale

Keep the syllabus order. Pub/Sub first because it's the simplest, most fundamental pattern (publish/subscribe) and topic 3 (Scheduler) reuses its topic directly. Eventarc second, as a deliberately *different* trigger source (a GCP resource event, not an app-level message) right after Pub/Sub so the contrast is fresh. Cloud Tasks and API Gateway close the module as the two "controlled access" patterns — one for internal reliability, one for external exposure.

## Per-Component Focus

### 1. Pub/Sub
**Land this one idea:** "A publisher and a subscriber never talk to each other directly — the topic is the only thing either of them knows about."
- Demo: create the topic, deploy `digest-worker-pubsub`, publish a test message with `gcloud pubsub topics publish`, watch the logs, check Telegram.
- Common confusion: students expect the publisher to get a response back. It doesn't — publish is fire-and-forget; the "response" is whatever downstream effect the subscriber causes (a Telegram message, in this case).

### 2. Eventarc
**Land this one idea:** "This isn't a message someone wrote — it's GCP itself noticing something happened and routing that notice for you."
- Demo: create the bucket, deploy `digest-worker-storage`, upload a `feeds.txt`, watch the function fire without anyone calling anything directly.
- Common confusion: students think Eventarc and Pub/Sub are competing options. Mention explicitly: Pub/Sub-triggered Cloud Functions actually run on Eventarc under the hood too — Eventarc's real distinguishing feature is routing many *kinds* of GCP events (storage, Firestore, Cloud Audit Logs), not just Pub/Sub messages.

### 3. Cloud Scheduler
**Land this one idea:** "This is the piece Module 14 promised — a cron job is genuinely this simple."
- Demo: create the job targeting topic 1's Pub/Sub topic, then trigger it manually with `gcloud scheduler jobs run` instead of waiting for the actual schedule, so the demo doesn't require an overnight wait.
- Common confusion: students assume Scheduler needs its own dedicated function. It doesn't — reusing topic 1's Pub/Sub topic as the target is the whole point here, and a nice callback moment.

### 4. Cloud Tasks
**Land this one idea:** "Not fire-and-forget like Pub/Sub — Cloud Tasks targets ONE specific endpoint, with retries and rate control, per task."
- Demo: create the queue, deploy `digest-worker-http`, run `04_create_tasks.py` with a small list of feeds, show the queue's dashboard with tasks executing (and retrying, if you simulate a failure).
- Common confusion: conflating this with Pub/Sub. Contrast directly: Pub/Sub is "broadcast to anyone listening," Cloud Tasks is "guarantee this exact call happens, with control over pacing."

### 5. API Gateway
**Land this one idea:** "Everything else this module built assumes the caller has a Google Cloud identity. This is the one pattern that doesn't — a plain API key, like any public API you've ever used."
- This is the most setup-heavy topic — budget real time, and don't skip the OpenAPI spec explanation; it's genuinely a new artifact type for this course.
- Demo: deploy the API config + gateway, create an API key, test with `curl ...?key=...` — no `gcloud auth print-identity-token` anywhere in this one, which is worth calling out explicitly as the whole point.

## Wrap-up

- Quick recap table: which of the 5 patterns fits which kind of caller (a script you wrote, a GCP event, a clock, a batch job, an external app)
- Rapid-fire recap: one question from each topic's "Quick Recap" (5 questions)
- Explicitly acknowledge: Module 14's Cloud Scheduler callback is now resolved — the Daily News Digest Bot story is complete

# Module 14 — Deploying AI Applications — commands.md

Real, literal commands run on this machine (macOS), in the order they were
run, against GCP project `gcp-fde-project`. The original `.bat` files (which
hardcode `PROJECT_ID=agentic-ai-capstone-1`, a project not accessible from
this account) live in `bat-files/` for reference only — every command below
was actually executed with the real values shown.

## 0. One-time project setup

```bash
gcloud config set project gcp-fde-project
gcloud config list
# [core]
# account = mentordivesh@gmail.com
# project = gcp-fde-project

gcloud auth application-default print-access-token >/dev/null && echo "ADC already set up"
# ADC was already set up from a prior module — no need to re-run
# `gcloud auth application-default login`

gcloud billing projects describe gcp-fde-project --format="value(billingEnabled)"
# True

gcloud services list --enabled --project=gcp-fde-project --format="value(config.name)"
# Already enabled: run.googleapis.com, artifactregistry.googleapis.com,
# secretmanager.googleapis.com, cloudbuild.googleapis.com, iam.googleapis.com
# Missing: cloudfunctions.googleapis.com

gcloud services enable cloudfunctions.googleapis.com --project=gcp-fde-project
# Operation "operations/acf.p2-1039893753206-1c709b4c-50ed-49e2-9379-0612854aee36" finished successfully.
```

Repo-level `.gitignore` was added before any `.env` file was created
(covers `.env`, `.venv/`, `__pycache__/`, etc. — see `../.gitignore`).

Original `.bat` files moved into `bat-files/` (`git mv`, kept for reference,
not deleted).

No local Python venv needed for this module — `requirements.txt` at the
module root confirms everything runs inside Docker / the Cloud Function
deploy itself, nothing installs on the host.

## 1. Docker build + local test — `news-summarizer`

```bash
docker info >/dev/null 2>&1 && echo "Docker daemon running"
# Docker daemon running

cd news_summarizer
docker build -t news-summarizer-local .
# Successfully built e9ad29e2d5d7
# Successfully tagged news-summarizer-local:latest

docker run --rm -p 8080:8080 \
  --env-file ../.env \
  -e PORT=8080 \
  -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys/adc.json \
  -v "$HOME/.config/gcloud/application_default_credentials.json:/tmp/keys/adc.json:ro" \
  --name news-summarizer-local-test \
  news-summarizer-local
```

**Gotcha not in the original `.bat`:** the Dockerfile's `CMD` is
`gunicorn --bind :$PORT ...` — `$PORT` must be set explicitly with `-e
PORT=8080` when running locally (Cloud Run sets it automatically, but a
bare local `docker run` does not). Without it gunicorn fails to bind.

macOS ADC path is `~/.config/gcloud/application_default_credentials.json`
(the original `.bat`'s `%APPDATA%\gcloud\...` is Windows-only).

Test call, from a second terminal:

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"headlines": ["Test headline one", "Test headline two"]}' \
  http://localhost:8080/
```

Result (expected, matches the module's designed failure sequence — the
secret doesn't exist until topic 5):

```json
{"error":"could not read secret: 404 Secret [projects/1039893753206/secrets/telegram-bot-token] not found or has no versions."}
```

Verified independently, two ways:
- `docker logs news-summarizer-local-test` shows gunicorn started clean and
  the Gemini `generate_content` call completed with no error (only a benign
  "use AFC in Chat.send_message instead" advisory) — so Vertex AI access
  from the container genuinely works; the 404 is only Secret Manager.
- `gcloud secrets list --project=gcp-fde-project --filter="name:telegram-bot-token"`
  → `Listed 0 items` — confirms the secret really doesn't exist yet, this
  isn't a masked auth bug.

```bash
docker stop news-summarizer-local-test
```

## 2. Artifact Registry

```bash
gcloud artifacts repositories list --project=gcp-fde-project --location=us-central1 --filter="name:deploying-ai-apps"
# Listed 0 items — didn't exist yet

gcloud artifacts repositories create deploying-ai-apps \
  --repository-format=docker \
  --location=us-central1 \
  --description="Deploying AI Applications module" \
  --project=gcp-fde-project
# Created repository [deploying-ai-apps].

gcloud auth configure-docker us-central1-docker.pkg.dev --quiet
# Docker configuration file updated.

docker tag news-summarizer-local us-central1-docker.pkg.dev/gcp-fde-project/deploying-ai-apps/news-summarizer:v1
docker push us-central1-docker.pkg.dev/gcp-fde-project/deploying-ai-apps/news-summarizer:v1
# v1: digest: sha256:e9ad29e2d5d78e0a8527bd868a54dc04327714fab2dc0cfc191a17080f787506 size: 2056

gcloud artifacts docker images list us-central1-docker.pkg.dev/gcp-fde-project/deploying-ai-apps --project=gcp-fde-project
# Confirms the image is present, size 79817689 bytes
```

## 3. Cloud Run deploy — `news-summarizer`

```bash
gcloud iam service-accounts create news-summarizer-sa \
  --display-name="News Summarizer Runtime SA" --project=gcp-fde-project
gcloud iam service-accounts create news-fetcher-sa \
  --display-name="News Fetcher Runtime SA" --project=gcp-fde-project
# Both created, zero extra IAM roles yet (deliberate — see topic 6)

gcloud run deploy news-summarizer \
  --image=us-central1-docker.pkg.dev/gcp-fde-project/deploying-ai-apps/news-summarizer:v1 \
  --region=us-central1 \
  --no-allow-unauthenticated \
  --service-account=news-summarizer-sa@gcp-fde-project.iam.gserviceaccount.com \
  --set-env-vars=PROJECT_ID=gcp-fde-project,LOCATION=us-central1,TELEGRAM_CHAT_ID=8966022242,SECRET_NAME=telegram-bot-token \
  --project=gcp-fde-project
```

**Real bug hit (not in the original module — Windows machines are x86_64 by
default, so this never surfaced there):** first deploy failed with
`Application failed to start: failed to load /bin/sh: exec format error`.
Root-caused, not worked around:

```bash
uname -m
# arm64  (this machine is Apple Silicon)
docker inspect news-summarizer-local --format='{{.Architecture}}'
# arm64  — the image built in topic 1 is arm64; Cloud Run requires linux/amd64
```

Plain `docker build --platform=linux/amd64 ...` failed too (`found but does
not provide the specified platform`) — the classic Docker builder can't
cross-compile without `buildx`, which wasn't installed:

```bash
brew install docker-buildx
# then add "cliPluginsExtraDirs": ["/opt/homebrew/lib/docker/cli-plugins"]
# to ~/.docker/config.json (already present here)
docker buildx ls
# builder "colima" already supports linux/amd64 — no extra QEMU setup needed

cd news_summarizer
docker buildx build --platform=linux/amd64 \
  -t us-central1-docker.pkg.dev/gcp-fde-project/deploying-ai-apps/news-summarizer:v1 \
  --push .
```

```bash
docker buildx imagetools inspect us-central1-docker.pkg.dev/gcp-fde-project/deploying-ai-apps/news-summarizer:v1
# Platform: linux/amd64 — confirmed correct this time

gcloud run deploy news-summarizer \
  --image=us-central1-docker.pkg.dev/gcp-fde-project/deploying-ai-apps/news-summarizer:v1 \
  --region=us-central1 \
  --no-allow-unauthenticated \
  --service-account=news-summarizer-sa@gcp-fde-project.iam.gserviceaccount.com \
  --set-env-vars=PROJECT_ID=gcp-fde-project,LOCATION=us-central1,TELEGRAM_CHAT_ID=8966022242,SECRET_NAME=telegram-bot-token \
  --project=gcp-fde-project
# Service URL: https://news-summarizer-1039893753206.us-central1.run.app
```

Test call:

```bash
ID_TOKEN=$(gcloud auth print-identity-token)
curl -X POST -H "Authorization: Bearer $ID_TOKEN" -H "Content-Type: application/json" \
  -d '{"headlines": ["Test headline one"]}' \
  https://news-summarizer-1039893753206.us-central1.run.app
```

**Second real bug hit, this one in the module's own IAM design (not just
this environment):** the test returned a bare 500 HTML page, not the
documented "secret not found" JSON error. Read the actual traceback via
`gcloud logging read` rather than guessing:

```bash
gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=news-summarizer AND severity>=ERROR' --project=gcp-fde-project --limit=5
```

Real cause: `google.genai.errors.ClientError: 403 PERMISSION_DENIED ...
Permission 'aiplatform.endpoints.predict' denied` — `news-summarizer-sa` had
zero IAM roles (correct, per topic 6's design), but **topic 6's own script
never grants Vertex AI access either** — only
`roles/secretmanager.secretAccessor` and `roles/run.invoker`. Confirmed
independently before "fixing" anything:

```bash
gcloud projects get-iam-policy gcp-fde-project --flatten="bindings[].members" \
  --filter="bindings.members:news-summarizer-sa" --format="table(bindings.role)"
# (no output — zero roles, confirmed)
```

This means the module's documented topic-6 IAM setup is incomplete — even
after granting both documented bindings, Gemini calls would still 403
forever. Fixed properly with the standard least-privilege role for calling
Vertex AI predict endpoints:

```bash
gcloud projects add-iam-policy-binding gcp-fde-project \
  --member="serviceAccount:news-summarizer-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user" \
  --condition=None
```

IAM propagation took about a minute. Retried until the response changed;
final state confirms the fix worked and the *documented* topic-3 failure
mode is now the one actually reached:

```json
{"error":"could not read secret: 403 Permission 'secretmanager.versions.access' denied on resource (or it may not exist). ..."}
```

**Baked in for future runs:** this grant is now part of `bat-files/00a_create_service_accounts.bat` itself (granted right after the SA is created, not deferred to topic 6) and `docs/06-iam.md` was checked and needs no change — it still genuinely grants exactly its documented two roles; this third one just isn't part of that topic's own story.

(Phrased as a permission-denied rather than a bare 404 "not found" — same
underlying cause the doc describes: the secret doesn't exist yet, created
in topic 5 — the summarizer SA has no IAM binding on it at all yet, so GCP
reports access-denied rather than distinguishing "doesn't exist" from "no
permission.")

## 4. Cloud Function deploy — `news-fetcher`

`.env`'s `SUMMARIZER_URL` updated to
`https://news-summarizer-1039893753206.us-central1.run.app` (topic 3's
printed URL) before this step.

```bash
cd news_fetcher
gcloud functions deploy news-fetcher \
  --gen2 --runtime=python311 --region=us-central1 --source=. \
  --entry-point=fetch_and_forward --trigger-http --no-allow-unauthenticated \
  --service-account=news-fetcher-sa@gcp-fde-project.iam.gserviceaccount.com \
  --set-env-vars=RSS_FEED_URL="https://news.google.com/rss/search?q=artificial+intelligence",SUMMARIZER_URL=https://news-summarizer-1039893753206.us-central1.run.app \
  --project=gcp-fde-project
# uri: https://news-fetcher-mewtpyvzkq-uc.a.run.app

ID_TOKEN=$(gcloud auth print-identity-token)
curl -X GET -H "Authorization: Bearer $ID_TOKEN" https://news-fetcher-mewtpyvzkq-uc.a.run.app
```

Result: `{"error":"no headlines found in feed"}` — not the documented "expect
a 403" failure.

**Third real bug hit, root-caused with temporary debug logging (added to
`main.py`, tested, then removed once diagnosed — not left in place):**

```bash
gcloud functions logs read news-fetcher --region=us-central1 --gen2 --project=gcp-fde-project --limit=20
# DEBUG feed.status=503 bozo=1 bozo_exception=<unknown>:2:252: not well-formed (invalid token)
```

Reproduced locally first to rule out a code bug — `feedparser.parse()`
against the same URL from this laptop returns `status=302` and 100 real
entries. The difference is the network origin, not the code. Confirmed by
capturing the raw response body from inside the deployed function:

```
DEBUG raw status=503 body_head='<html>...<title>Sorry...</title>...<font color=#4285f4>G</font>...'
```

That's Google's own bot-detection "Sorry..." block page — `news.google.com`
returns it specifically to Google Cloud's shared egress IP ranges, not to
this UA or query. Tried a real browser `User-Agent` header first (a
plausible, narrower fix) — made no difference, confirming this is IP-based,
not UA-based, and not something fixable inside our own service. Not a
retry-able transient error either (Google's own outbound-traffic module,
still on branch `1`/module 14 as of this run — reproduced identically
across three separate deploys).

**Fix:** switched the feed off Google News entirely to a source that
doesn't block cloud egress ranges. Verified candidates from this laptop
first, then confirmed the actual choice against the real deployed function
(that's the only environment that matters here):

```bash
curl -s -o /dev/null -w "status=%{http_code}\n" -A "Mozilla/5.0" "https://techcrunch.com/tag/artificial-intelligence/feed/"
# status=200
```

Updated `RSS_FEED_URL`'s default in `news_fetcher/main.py`, `.env`, and
`.env.example` (kept in sync per the playbook) to
`https://techcrunch.com/tag/artificial-intelligence/feed/`. Kept the
browser `User-Agent` header on the `feedparser.parse()` call as a general
defensive default for other feeds, even though it wasn't the fix for this
specific block.

```bash
gcloud functions deploy news-fetcher \
  --gen2 --runtime=python311 --region=us-central1 --source=. \
  --entry-point=fetch_and_forward --trigger-http --no-allow-unauthenticated \
  --service-account=news-fetcher-sa@gcp-fde-project.iam.gserviceaccount.com \
  --set-env-vars=RSS_FEED_URL="https://techcrunch.com/tag/artificial-intelligence/feed/",SUMMARIZER_URL=https://news-summarizer-1039893753206.us-central1.run.app \
  --project=gcp-fde-project

ID_TOKEN=$(gcloud auth print-identity-token)
curl -X GET -H "Authorization: Bearer $ID_TOKEN" https://news-fetcher-mewtpyvzkq-uc.a.run.app
```

Result: `500 Internal Server Error` (bare HTML, no JSON) — confirmed via
`gcloud functions logs read` to be a `requests.exceptions.JSONDecodeError`
inside `main.py`'s unguarded `response.json()` call, because
`news-summarizer` actually returned Cloud Run's own non-JSON 403 body (the
fetcher's SA has no `run.invoker` role yet). This **is** the module's
documented topic-4 "expect a 403" failure — it just surfaces as a Python
exception instead of a passed-through 403, because `main.py` calls
`response.json()` unconditionally. Left as-is (matches the module's
intended teaching point for this topic; topic 6 resolves it for real).

## 5. Secret Manager — Telegram bot token

```bash
gcloud secrets create telegram-bot-token --replication-policy=automatic --project=gcp-fde-project
# Created secret [telegram-bot-token].

# Sourced from .env into a shell variable, never typed literally in the
# command itself, per the playbook's live-secret rule:
set -a && source .env && set +a
printf '%s' "$TELEGRAM_BOT_TOKEN" | gcloud secrets versions add telegram-bot-token --data-file=- --project=gcp-fde-project
# Created version [1] of the secret [telegram-bot-token].

gcloud secrets versions list telegram-bot-token --project=gcp-fde-project
# NAME  STATE    CREATED
# 1     enabled  2026-09-17T18:15:10
```

Retest `news-summarizer` directly:

```bash
ID_TOKEN=$(gcloud auth print-identity-token)
curl -X POST -H "Authorization: Bearer $ID_TOKEN" -H "Content-Type: application/json" \
  -d '{"headlines": ["Test headline one"]}' \
  https://news-summarizer-1039893753206.us-central1.run.app
```

Result unchanged from topic 3's post-fix state —
`could not read secret: 403 Permission 'secretmanager.versions.access'
denied` — exactly as documented: the secret now exists, but
`news-summarizer-sa` still has no access to it. That's topic 6.

## 6. IAM — wiring the two services together

```bash
gcloud secrets add-iam-policy-binding telegram-bot-token \
  --member="serviceAccount:news-summarizer-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project=gcp-fde-project

gcloud run services add-iam-policy-binding news-summarizer \
  --region=us-central1 \
  --member="serviceAccount:news-fetcher-sa@gcp-fde-project.iam.gserviceaccount.com" \
  --role="roles/run.invoker" \
  --project=gcp-fde-project
```

**Note:** a third IAM binding was actually required beyond these two
documented ones — `roles/aiplatform.user` on `news-summarizer-sa`, granted
earlier during topic 3 once the Vertex AI 403 was root-caused (see topic 3
above). Without it, these two bindings alone would not have been enough to
make the pipeline work — the module's own topic 6 script is missing that
binding.

Full pipeline test:

```bash
ID_TOKEN=$(gcloud auth print-identity-token)
curl -X GET -H "Authorization: Bearer $ID_TOKEN" https://news-fetcher-mewtpyvzkq-uc.a.run.app
```

First several attempts still returned `500 Internal Server Error` — IAM
propagation delay, same as topic 3 (took roughly 60-90 seconds this time).
Polled until it changed rather than declaring failure early. Final result:

```json
{"status":"sent","summary":"Here's a quick look at today's top stories:\n\n*   **AI Ethics & Privacy Concerns:** ...","telegram_status":200}
```

**Independently verified** (not just trusting the JSON's `telegram_status`)
by sending a second, direct message through the same bot token/chat ID via
`curl https://api.telegram.org/bot<TOKEN>/sendMessage` and confirming via
the returned `message_id` sequence that a message really was delivered to
this chat between the earlier manual "hi" and this verification ping — i.e.
the pipeline's own digest message genuinely went through, not just a
locally-fabricated success response. Also visually confirmed in the
Telegram app.

## 7. Live config updates (no rebuild)

```bash
# Cloud Run side - genuinely no rebuild
gcloud run services describe news-summarizer --region=us-central1 --project=gcp-fde-project \
  --format="value(status.latestReadyRevisionName,spec.template.spec.containers[0].image)"
# news-summarizer-00002-ggc   .../news-summarizer:v1

gcloud run services update news-summarizer \
  --region=us-central1 \
  --update-env-vars=TELEGRAM_CHAT_ID=8966022242 \
  --project=gcp-fde-project

gcloud run services describe news-summarizer --region=us-central1 --project=gcp-fde-project \
  --format="value(status.latestReadyRevisionName,spec.template.spec.containers[0].image)"
# news-summarizer-00003-wz7   .../news-summarizer:v1   <- new revision, IDENTICAL image reference
```

```bash
# Cloud Functions side
cd news_fetcher
gcloud functions deploy news-fetcher \
  --gen2 --region=us-central1 \
  --update-env-vars=RSS_FEED_URL="https://techcrunch.com/tag/cloud-computing/feed/" \
  --project=gcp-fde-project
```

**Real discrepancy from the module's own claim, verified not assumed:** the
module's topic 7 says "no docker build, no docker push, no new image
anywhere — just new configuration." True for the Cloud Run service (image
digest identical, confirmed above). **Not true for the Cloud Function** —
compared the image digest before and after an env-var-only
`gcloud functions deploy`:

```bash
gcloud run revisions describe news-fetcher-00007-dim --region=us-central1 --project=gcp-fde-project --format="value(spec.containers[0].image)"
# ...@sha256:5fec5f19733f4bad50cf4de5ef60b447e7b84444f32884dbeb09c0e3856d0583
gcloud run revisions describe news-fetcher-00008-vub --region=us-central1 --project=gcp-fde-project --format="value(spec.containers[0].image)"
# ...@sha256:48b5e4139bf5702ad27ceef74ff6681ef4c36cfe296ee07106a1db8107d00609  <- DIFFERENT digest
```

A new Cloud Build (`build: .../builds/a549107e-...`) actually ran and
produced a new image. `gcloud functions deploy` (source-based, gen2)
re-triggers the buildpacks pipeline on every deploy, including
env-var-only changes — unlike `gcloud run services update` on an
already-built image. The env var change itself still worked with no code
change required, which is topic 7's real teaching point; the "no rebuild
at all" framing just doesn't hold for the Cloud Functions half specifically.

Full pipeline retested after both changes — still works, and the digest
content changed topic (cloud-computing headlines now), confirming the new
`RSS_FEED_URL` genuinely took effect:

```bash
ID_TOKEN=$(gcloud auth print-identity-token)
curl -X GET -H "Authorization: Bearer $ID_TOKEN" https://news-fetcher-mewtpyvzkq-uc.a.run.app
# {"status":"sent","summary":"...OpenAI and Amazon inked a massive $38 billion cloud computing deal...","telegram_status":200}
```

**Baked in for future runs:** both the RSS feed fix (topic 4) and this
build-vs-no-build distinction are now reflected in `.env.example`,
`bat-files/00_setup_vars.bat`, `bat-files/07_update_env_vars_demo.bat`,
`docs/04-cloud-functions.md`, and `docs/07-environment-variables.md`, so a
future run of this module won't rediscover either from scratch.

## Final cleanup

_Pending — run when the module is fully demoed and verified._

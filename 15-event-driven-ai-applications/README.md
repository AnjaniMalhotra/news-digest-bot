# Code — Module 15: Event-Driven AI Applications

One small worker (`digest_worker/`), deployed three different ways (`digest-worker-pubsub`, `digest-worker-storage`, `digest-worker-http`), triggered five different ways across this module's topics. **Directly continues Module 14's Daily News Digest Bot** — rebuilt fresh here per the course's isolation rule, but the same story.

## Setup (do this once)

```bat
copy .env.example .env
REM ...fill in real values, including your Telegram bot token and chat ID
pip install -r requirements.txt
gcloud auth application-default login
00_setup_vars.bat
00a_initial_setup.bat
```

`bat-files/` holds the original Windows-only `.bat` scripts for reference (the exact `gcloud`/`docker` commands each topic needs) — they don't run on macOS/Linux. `commands.md` at this module's root is the actual, real, literal command-by-command record of what was run on this machine, in the order it was run — including the six real IAM/config bugs found and fixed along the way that this module's original scripts didn't account for.

## Files

| File / Folder | Matches Doc Topic | What It Does |
|------|--------------------|---------------|
| `.env.example` | — | Every config key this module needs |
| `bat-files/00_setup_vars.bat` | — | Config for every other `.bat` script |
| `bat-files/00a_initial_setup.bat` | — | Service accounts + the Telegram secret + the worker's baseline Vertex AI access, created once upfront |
| `digest_worker/` | — | The shared function source: `main.py` (3 entry points), `requirements.txt` |
| `bat-files/01_pubsub_setup.bat` | 1 | Create the topic, deploy `digest-worker-pubsub`, publish a test message |
| `bat-files/02_eventarc_setup.bat` | 2 | Create the bucket, deploy `digest-worker-storage`, upload a test file |
| `bat-files/03_cloud_scheduler_setup.bat` | 3 | A daily job targeting topic 1's Pub/Sub topic |
| `bat-files/04_cloud_tasks_setup.bat` | 4 | Queue + `digest-worker-http` deploy + IAM binding |
| `04_create_tasks.py` | 4 | Enqueues one Cloud Task per feed, with an OIDC token attached |
| `05_openapi_spec.yaml` | 5 | The API Gateway config — edit in the real function URL before deploying |
| `bat-files/05_api_gateway_setup.bat` | 5 | Deploys the API, config, gateway, and an API key |
| `bat-files/99_cleanup.bat` | — | Tears everything down — good hygiene, even though it's all free-tier |

## How to run these — order matters

1. `bat-files/00_setup_vars.bat`, then `bat-files/00a_initial_setup.bat`
2. `bat-files/01_pubsub_setup.bat` (topic 1)
3. `bat-files/02_eventarc_setup.bat` (topic 2)
4. `bat-files/03_cloud_scheduler_setup.bat` (topic 3) — reuses topic 1's Pub/Sub topic, no new function
5. `bat-files/04_cloud_tasks_setup.bat` (topic 4) — **copy the printed function URL into `.env`/`bat-files/00_setup_vars.bat` as `WORKER_HTTP_URL`**, then `python 04_create_tasks.py`
6. Edit `05_openapi_spec.yaml`, replacing `WORKER_HTTP_URL_HERE` with the same URL from step 5, then `bat-files/05_api_gateway_setup.bat` (topic 5)
7. `bat-files/99_cleanup.bat` when you're done with the module

## Cost note

Pub/Sub (10 GiB/month free), Cloud Scheduler (3 free jobs/month per billing account), Cloud Tasks (1 million free operations/month), and API Gateway (2 million free calls/month) all comfortably cover this module. Eventarc has no separate charge beyond its Pub/Sub transport layer. Same free-tier-friendly profile as Module 14 — no provision/teardown cost discipline needed, though `bat-files/99_cleanup.bat` is still good practice.

# News Digest Bot — Deploy, Automate, Observe

A small personal AI tool — fetch today's headlines, summarize them with Gemini, send the digest to Telegram — built in three stages, one per branch, each stage adding the next real production skill on top of the last.

There is deliberately **no code on this `main` branch**. The stages are **cumulative** — each branch contains everything from the ones before it:

| Branch | Contains | Stage | What it adds |
|---|---|---|---|
| [`14-deploying-ai-applications`](../../tree/14-deploying-ai-applications) | Module 14 | **Deploy** | Containerize the summarizer (Docker), host the image (Artifact Registry), run it live (Cloud Run), add a lighter fetcher (Cloud Functions), store the Telegram token properly (Secret Manager), and wire the two services together with least-privilege IAM |
| [`15-event-driven-ai-applications`](../../tree/15-event-driven-ai-applications) | Modules 14 + 15 | **Automate** | The same worker learns to trigger itself — five different ways: a message (Pub/Sub), a file landing in a bucket (Eventarc), a daily cron (Cloud Scheduler), a reliable per-item queue (Cloud Tasks), and a public API-key-protected front door (API Gateway) |
| [`16-monitoring-observability`](../../tree/16-monitoring-observability) | Modules 14 + 15 + 16 | **Observe** | The same idea again, rebuilt as one instrumented service with two switches that deliberately break it (`simulate_error`, `simulate_slow`) — proving structured logging, error grouping, request tracing, a custom metric, and a real alert all actually work before trusting them |

## The throughline

Module 14 ends on purpose with one real gap: the pipeline only runs when *you* call it over HTTP. Module 15 closes that gap with five different automatic triggers. Module 16 then asks the question neither of the first two answers: once it's deployed and triggering itself, how do you actually know what it's doing? Each module rebuilds the digest bot fresh rather than importing the previous module's code, but the underlying idea — and the lesson — carries forward.

## How the branches work

Each module lives in its own folder (`14-deploying-ai-applications/`, `15-event-driven-ai-applications/`, `16-monitoring-observability/`), self-contained with its own docs, `.env.example`, and `commands.md` (the real, literal commands that were run against GCP). The branches are checkpoints along the way: checking out an earlier branch shows the project exactly as it stood at that stage, and the last branch, `16-monitoring-observability`, holds all three modules together.

## Getting started

Check out the branch for the stage you want — or `16-monitoring-observability` to get everything at once — then open the module folder you want to work through. Each module's `README.md` has its own setup instructions.

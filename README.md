# News Digest Bot — Deploy, Automate, Observe

A small personal AI tool — fetch today's headlines, summarize them with Gemini, send the digest to Telegram — built three times, once per branch, each time adding the next real production skill on top of the last.

There is deliberately **no code on this `main` branch**. Each stage of the story lives on its own branch:

| Branch | Stage | What it adds |
|---|---|---|
| [`1`](../../tree/1) | **Deploy** | Containerize the summarizer (Docker), host the image (Artifact Registry), run it live (Cloud Run), add a lighter fetcher (Cloud Functions), store the Telegram token properly (Secret Manager), and wire the two services together with least-privilege IAM |
| [`2`](../../tree/2) | **Automate** | The same worker learns to trigger itself — five different ways: a message (Pub/Sub), a file landing in a bucket (Eventarc), a daily cron (Cloud Scheduler), a reliable per-item queue (Cloud Tasks), and a public API-key-protected front door (API Gateway) |
| [`3`](../../tree/3) | **Observe** | The same idea again, rebuilt as one instrumented service with two switches that deliberately break it (`simulate_error`, `simulate_slow`) — proving structured logging, error grouping, request tracing, a custom metric, and a real alert all actually work before trusting them |

## The throughline

Branch `1` ends on purpose with one real gap: the pipeline only runs when *you* call it over HTTP. Branch `2` closes that gap with five different automatic triggers. Branch `3` then asks the question neither of the first two answers: once it's deployed and triggering itself, how do you actually know what it's doing? Each branch rebuilds the digest bot fresh rather than importing the previous branch's code, but the underlying idea — and the lesson — carries forward.

## Why three branches instead of one repo with everything in it

Each stage is a complete, independently runnable lesson: an inbound webhook (branch 1), an autonomous worker (branch 2), and a monitored service (branch 3) are three different shapes of "the same app," not three parts of one build. Keeping them on separate branches means each one can be checked out, read, and run on its own without the other two stages' files in the way.

## Getting started

Check out whichever branch matches what you want to learn — each one is self-contained, with its own setup instructions and `.env.example` inside.

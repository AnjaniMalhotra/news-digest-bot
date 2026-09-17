# Teacher Plan — Module 14: Deploying AI Applications

**Total time:** 4 hrs (240 min) — includes an unusually large 55 min buffer. Deployment work hits more real, live friction than pure-Python modules (build errors, permission errors, cold starts) — budget for it honestly.

## Before you start recording/teaching

- [ ] **Run through the entire pipeline yourself, start to finish, before recording.** Every command, every expected failure, every fix. This module has more moving parts than almost anything earlier in the course.
- [ ] Docker Desktop installed and running
- [ ] A Telegram bot created via @BotFather, token in hand, plus your personal chat ID
- [ ] `.env` filled in
- [ ] `bat-files/00_setup_vars.bat` and `bat-files/00a_create_service_accounts.bat` already run once
- [ ] Have `bat-files/99_cleanup.bat` ready — not for cost reasons this time (everything's free-tier), just good hygiene to demonstrate

## Suggested pacing (240 min)

| # | Topic | Minutes | Format |
|---|-------|---------|--------|
| 1 | Docker | 30 | Build + run locally |
| 2 | Artifact Registry | 20 | Push the image |
| 3 | Cloud Run | 35 | Deploy, test, watch it fail informatively |
| 4 | Cloud Functions | 30 | Deploy, test, watch it fail differently |
| 5 | Secret Manager | 25 | Create the secret, retry, watch it fail a third way |
| 6 | IAM | 25 | Grant the bindings — everything finally works |
| 7 | Environment Variables | 20 | Change config live, no rebuild |
| — | Full pipeline demo + buffer | 55 | — |

## Teaching order rationale

Keep the syllabus order — it happens to trace the natural build order of any containerized service: build it (Docker), store it (Artifact Registry), run it (Cloud Run), then add the second, lighter service (Cloud Functions) that calls it. Secret Manager and IAM come after both services are deployed specifically so their absence is visible and motivating, not abstract.

## Per-Component Focus

### 1. Docker
**Land this one idea:** "A container is a promise — it runs the same way on your laptop and on Google's servers, because it's not actually running on either, it's running inside its own tiny environment."
- Demo: build the image, run it locally with the ADC-credential-mount trick (see the doc — mounting just `application_default_credentials.json`, not your whole gcloud config), hit `localhost:8080` with curl.
- Common confusion: students expect the container to "just work" with their gcloud login automatically. Explain explicitly why credentials have to be deliberately passed in — the container is isolated by design.

### 2. Artifact Registry
**Land this one idea:** "This is just a private, GCP-hosted version of Docker Hub — nothing conceptually new, just where the image lives before Cloud Run can use it."
- Demo: create the repo, `gcloud auth configure-docker`, tag, push. Keep this fast — it's a short, mechanical topic.

### 3. Cloud Run
**Land this one idea:** "Cloud Run turns a container into a URL — and we're deploying it locked down (`--no-allow-unauthenticated`) on purpose."
- Demo: deploy, then try calling it with `gcloud auth print-identity-token` — it responds, but fails with a "secret not found" error. **This is expected — say so explicitly, don't apologize for it.** Point forward to topic 5.
- Common confusion: students think `--no-allow-unauthenticated` is broken because "the request didn't work." Clarify: authentication succeeded; a *different* thing (the secret) is what's missing right now.

### 4. Cloud Functions
**Land this one idea:** "Two different deployment targets for two different-shaped workloads — light and event-driven vs. heavier and container-based."
- Demo: deploy `news-fetcher`, call it — it fails with a 403 from Cloud Run, because the function's service account isn't authorized to invoke the summarizer yet. Again, expected — point forward to topic 6.
- Common confusion: students think a 403 means something is broken in their code. It's IAM doing exactly its job — the deploy succeeded, the *permission* is what's missing.

### 5. Secret Manager
**Land this one idea:** "Secrets are not environment variables — they're versioned, access-controlled, and never sit in plain text in your deploy command."
- Demo: create the secret, add the Telegram token as a version, then retry hitting `news-summarizer` directly. The error changes — no longer "not found," now "permission denied." That shift IS the lesson: the secret exists, but access isn't granted yet.
- Common confusion: conflating this with topic 7 (env vars). Use the changed error message as the live proof of the difference — env vars would just show up; secrets need an explicit access grant, which is exactly topic 6.

### 6. IAM
**Land this one idea:** "Two service accounts, two narrow grants — `secretAccessor` for the summarizer, `run.invoker` for the fetcher — and now, for the first time, the whole pipeline actually works."
- This is the payoff moment of the module. Grant both bindings, then run the full pipeline live: call `news-fetcher`, watch it call `news-summarizer`, watch a real message land in Telegram.
- Common confusion: students want to grant broader roles "to stop the errors faster." Reinforce least privilege explicitly — each grant maps to exactly one thing that service needs to do, nothing more.

### 7. Environment Variables
**Land this one idea:** "Config you'd want to change without touching code — chat ID, feed URL — belongs here, not hardcoded and not in Secret Manager."
- Demo: `gcloud run services update ... --update-env-vars=...` to change the summarizer's `TELEGRAM_CHAT_ID` live, without rebuilding or redeploying the container image. Note for the Cloud Functions side specifically: `gcloud functions deploy --update-env-vars` *does* re-trigger a build (new image digest) even for an env-var-only change — only the Cloud Run update is genuinely build-free. Worth calling out explicitly so it doesn't read as a contradiction.
- Common confusion: "why isn't the Telegram token an env var too, if this is so easy?" Good question to ask the class/viewers directly — the answer is exactly topic 5's lesson (env vars aren't access-controlled or versioned the way secrets are).

## Wrap-up

- Run the full pipeline one final time, live, for the camera
- Rapid-fire recap: one question from each topic's "Quick Recap" (7 questions)
- Explicitly mention: Cloud Scheduler / event-driven triggers are still ahead, in Module 15

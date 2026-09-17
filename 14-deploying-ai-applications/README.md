# Code — Module 14: Deploying AI Applications

Two small services, deployed two different ways, building up piece by piece across the module's 7 topics: **`news-fetcher`** (Cloud Function) calls **`news-summarizer`** (Cloud Run, Docker container), which summarizes headlines with Gemini and sends the result to your personal Telegram.

**The pipeline doesn't fully work until topic 6.** Each earlier topic's test call fails with a specific, informative, expected error — see each `.bat` script's comments and the topic docs for exactly what to expect and why. This is deliberate, not a bug in these instructions.

## Setup (do this once)

1. Install Docker Desktop, make sure it's running
2. Create a Telegram bot via [@BotFather](https://t.me/BotFather), get your token and chat ID (full steps in `docs/05-secret-manager.md`)
3. ```bat
   copy .env.example .env
   REM ...fill in real values, including your Telegram token and chat ID
   gcloud auth application-default login
   00_setup_vars.bat
   00a_create_service_accounts.bat
   ```

`bat-files/` holds the original Windows-only `.bat` scripts for reference (the exact `gcloud`/`docker` commands each topic needs) — they don't run on macOS/Linux. `commands.md` at this module's root is the actual, real, literal command-by-command record of what was run on this machine, in the order it was run.

## Files

| File / Folder | Matches Doc Topic | What It Does |
|------|--------------------|---------------|
| `.env.example` | — | Every config key this module needs |
| `bat-files/00_setup_vars.bat` | — | Config for every other `.bat` script |
| `bat-files/00a_create_service_accounts.bat` | — | Creates both runtime SAs early; grants `news-summarizer-sa` baseline Vertex AI access (needed just to call Gemini) — no other roles yet, on purpose |
| `news_summarizer/` | 1 | The Cloud Run service: `main.py`, `Dockerfile`, `requirements.txt` |
| `bat-files/01_docker_build_and_test_local.bat` | 1 | Build + run the summarizer locally |
| `bat-files/02_artifact_registry_push.bat` | 2 | Create the repo, push the image |
| `bat-files/03_deploy_cloud_run.bat` | 3 | Deploy the summarizer — expect a "secret not found" test failure |
| `news_fetcher/` | 4 | The Cloud Function: `main.py`, `requirements.txt` |
| `bat-files/04_deploy_cloud_function.bat` | 4 | Deploy the fetcher — expect a 403 test failure |
| `bat-files/05_secret_manager_setup.bat` | 5 | Create the Telegram token secret — the earlier error changes shape |
| `bat-files/06_iam_setup.bat` | 6 | Grant both IAM bindings — the full pipeline finally works |
| `bat-files/07_update_env_vars_demo.bat` | 7 | Change config on live services, no rebuild |
| `bat-files/99_cleanup.bat` | — | Tears everything down — good hygiene, even though it's all free-tier |

## How to run these — order matters, by design

1. `bat-files/00_setup_vars.bat`, then `bat-files/00a_create_service_accounts.bat`
2. `bat-files/01_docker_build_and_test_local.bat` (topic 1)
3. `bat-files/02_artifact_registry_push.bat` (topic 2)
4. `bat-files/03_deploy_cloud_run.bat` (topic 3) — **copy the printed service URL into `.env`/`bat-files/00_setup_vars.bat` as `SUMMARIZER_URL`** before continuing
5. `bat-files/04_deploy_cloud_function.bat` (topic 4)
6. `bat-files/05_secret_manager_setup.bat` (topic 5)
7. `bat-files/06_iam_setup.bat` (topic 6) — this is where it all finally connects
8. `bat-files/07_update_env_vars_demo.bat` (topic 7)
9. `bat-files/99_cleanup.bat` when you're done with the module

## Cost note

Cloud Run, Cloud Functions, Artifact Registry, and Secret Manager all have real Always Free allowances that comfortably cover this module's usage — see the module overview doc for the exact numbers. This is the first deployment module in the course that doesn't need Module 9's provision-then-teardown discipline for cost reasons (though `bat-files/99_cleanup.bat` is still good practice).

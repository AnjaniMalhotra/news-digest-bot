@echo off
REM Creates the two runtime service accounts BOTH deployed services will use.
REM Run this once, early, before topics 3-4's deploys reference them.
REM Requires: 00_setup_vars.bat already run in this same window.
REM
REM NOTE: these accounts get NO IAM roles related to THIS MODULE's own
REM lesson (secret access, service-to-service invoke) yet, on purpose -
REM topic 6 grants those, so their absence is visible and the "why do I
REM need IAM" lesson lands for real, not abstractly.
REM
REM The one exception: news-summarizer-sa needs roles/aiplatform.user just
REM to call Gemini at all - that's a baseline requirement unrelated to this
REM module's secretAccessor/run.invoker story, so it's granted here instead
REM of bundled into topic 6's "two narrow grants" lesson.

echo == creating the news-summarizer runtime service account ==
gcloud iam service-accounts create %SUMMARIZER_SA_NAME% ^
  --display-name="News Summarizer Runtime SA"

echo == creating the news-fetcher runtime service account ==
gcloud iam service-accounts create %FETCHER_SA_NAME% ^
  --display-name="News Fetcher Runtime SA"

echo == granting news-summarizer-sa baseline Vertex AI access (needed just to call Gemini) ==
gcloud projects add-iam-policy-binding %PROJECT_ID% ^
  --member="serviceAccount:%SUMMARIZER_SA_EMAIL%" ^
  --role="roles/aiplatform.user"

echo.
echo Both service accounts created. Neither has this module's own
echo secretAccessor/run.invoker roles yet - that's topic 6.

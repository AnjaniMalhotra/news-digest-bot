@echo off
REM One-time setup: service account, IAM roles it needs to WRITE logs/traces/
REM metrics (not just be observed - it's an active participant here), and
REM the Telegram secret.
REM Requires: 00_setup_vars.bat already run in this same window.

echo == creating the service's runtime service account ==
gcloud iam service-accounts create %WORKER_SA_NAME% ^
  --display-name="Digest Worker Observable Runtime SA"

echo == granting it permission to WRITE logs, traces, and custom metrics ==
echo (same least-privilege habit as every earlier module's IAM topic)
gcloud projects add-iam-policy-binding %PROJECT_ID% ^
  --member="serviceAccount:%WORKER_SA_EMAIL%" ^
  --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding %PROJECT_ID% ^
  --member="serviceAccount:%WORKER_SA_EMAIL%" ^
  --role="roles/cloudtrace.agent"

gcloud projects add-iam-policy-binding %PROJECT_ID% ^
  --member="serviceAccount:%WORKER_SA_EMAIL%" ^
  --role="roles/monitoring.metricWriter"

echo == granting it baseline Vertex AI access (needed just to call Gemini) ==
echo (Modules 14/15 found this is required and missing from the original
echo  script - applying the fix upfront here instead of rediscovering it)
gcloud projects add-iam-policy-binding %PROJECT_ID% ^
  --member="serviceAccount:%WORKER_SA_EMAIL%" ^
  --role="roles/aiplatform.user"

echo == creating the Telegram bot token secret ==
gcloud secrets create %SECRET_NAME% --replication-policy=automatic
echo %TELEGRAM_BOT_TOKEN% | gcloud secrets versions add %SECRET_NAME% --data-file=-

echo == letting the worker read that secret ==
gcloud secrets add-iam-policy-binding %SECRET_NAME% ^
  --member="serviceAccount:%WORKER_SA_EMAIL%" ^
  --role="roles/secretmanager.secretAccessor"

echo.
echo Setup complete.

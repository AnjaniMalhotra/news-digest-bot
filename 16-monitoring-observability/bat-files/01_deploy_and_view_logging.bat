@echo off
REM Topic 1 - Deploy digest-worker-observable, send a request, view its logs.
REM Requires: 00_setup_vars.bat + 00a_initial_setup.bat already run,
REM Docker Desktop running.

echo == deploying straight from source (Cloud Run builds the container for you) ==
gcloud run deploy %SERVICE_NAME% ^
  --source=digest_worker_observable ^
  --region=%REGION% ^
  --allow-unauthenticated ^
  --service-account=%WORKER_SA_EMAIL% ^
  --set-env-vars=PROJECT_ID=%PROJECT_ID%,LOCATION=%LOCATION%,TELEGRAM_CHAT_ID=%TELEGRAM_CHAT_ID%,SECRET_NAME=%SECRET_NAME%

echo.
echo == service URL (copy this into .env / 00_setup_vars.bat as SERVICE_URL) ==
gcloud run services describe %SERVICE_NAME% --region=%REGION% --format="value(status.url)"

echo.
echo == sending a normal request ==
echo Run this manually, replacing SERVICE_URL with the URL printed above:
echo   curl SERVICE_URL

echo.
echo == viewing recent logs ==
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=%SERVICE_NAME%" --limit=20 --format=json

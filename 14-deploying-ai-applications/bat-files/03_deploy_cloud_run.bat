@echo off
REM Topic 3 - Deploy news-summarizer to Cloud Run.
REM Requires: 00_setup_vars.bat + 00a_create_service_accounts.bat already run,
REM image already pushed (topic 2).

echo == deploying (locked down - no unauthenticated access) ==
gcloud run deploy %SUMMARIZER_SERVICE_NAME% ^
  --image=%REGION%-docker.pkg.dev/%PROJECT_ID%/%REPO_NAME%/news-summarizer:v1 ^
  --region=%REGION% ^
  --no-allow-unauthenticated ^
  --service-account=%SUMMARIZER_SA_EMAIL% ^
  --set-env-vars=PROJECT_ID=%PROJECT_ID%,LOCATION=%LOCATION%,TELEGRAM_CHAT_ID=%TELEGRAM_CHAT_ID%,SECRET_NAME=%SECRET_NAME%

echo.
echo == service URL (copy this into .env / 00_setup_vars.bat as SUMMARIZER_URL) ==
gcloud run services describe %SUMMARIZER_SERVICE_NAME% --region=%REGION% --format="value(status.url)"

echo.
echo == test it (expect a "secret not found" error right now - that's normal, see topic 5) ==
for /f %%i in ('gcloud auth print-identity-token') do set ID_TOKEN=%%i
echo Run this manually, replacing SERVICE_URL with the URL printed above:
echo   curl -X POST -H "Authorization: Bearer %ID_TOKEN%" -H "Content-Type: application/json" -d "{\"headlines\": [\"Test headline one\"]}" SERVICE_URL

@echo off
REM Topic 6 - Grant the two IAM bindings that finally make the pipeline work.
REM Requires: 00_setup_vars.bat already run, secret created (topic 5),
REM both services deployed (topics 3-4).

echo == letting news-summarizer's SA read the Telegram token secret ==
gcloud secrets add-iam-policy-binding %SECRET_NAME% ^
  --member="serviceAccount:%SUMMARIZER_SA_EMAIL%" ^
  --role="roles/secretmanager.secretAccessor"

echo == letting news-fetcher's SA invoke news-summarizer ==
gcloud run services add-iam-policy-binding %SUMMARIZER_SERVICE_NAME% ^
  --region=%REGION% ^
  --member="serviceAccount:%FETCHER_SA_EMAIL%" ^
  --role="roles/run.invoker"

echo.
echo == now run the FULL pipeline - this should actually work end to end ==
for /f %%i in ('gcloud auth print-identity-token') do set ID_TOKEN=%%i
echo Run this manually, replacing FUNCTION_URL with news-fetcher's URL:
echo   curl -X GET -H "Authorization: Bearer %ID_TOKEN%" FUNCTION_URL
echo.
echo Check your Telegram - a real digest should arrive within a few seconds.

@echo off
REM Topic 4 - Deploy news-fetcher to Cloud Functions (2nd gen).
REM Requires: 00_setup_vars.bat + 00a_create_service_accounts.bat already run,
REM AND SUMMARIZER_URL updated with the real URL from topic 3.

cd news_fetcher

echo == deploying (locked down - no unauthenticated access) ==
gcloud functions deploy %FETCHER_FUNCTION_NAME% ^
  --gen2 ^
  --runtime=python311 ^
  --region=%REGION% ^
  --source=. ^
  --entry-point=fetch_and_forward ^
  --trigger-http ^
  --no-allow-unauthenticated ^
  --service-account=%FETCHER_SA_EMAIL% ^
  --set-env-vars=RSS_FEED_URL=%RSS_FEED_URL%,SUMMARIZER_URL=%SUMMARIZER_URL%

cd ..

echo.
echo == function URL ==
gcloud functions describe %FETCHER_FUNCTION_NAME% --region=%REGION% --gen2 --format="value(serviceConfig.uri)"

echo.
echo == test it (expect a 403 from Cloud Run right now - that's normal, see topic 6) ==
for /f %%i in ('gcloud auth print-identity-token') do set ID_TOKEN=%%i
echo Run this manually, replacing FUNCTION_URL with the URL printed above:
echo   curl -X GET -H "Authorization: Bearer %ID_TOKEN%" FUNCTION_URL

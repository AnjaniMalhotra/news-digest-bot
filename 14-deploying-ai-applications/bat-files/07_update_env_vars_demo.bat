@echo off
REM Topic 7 - Change config on already-deployed services, no rebuild needed.
REM Requires: 00_setup_vars.bat already run, both services deployed.

echo == updating news-summarizer's TELEGRAM_CHAT_ID live ==
echo (Replace NEW_CHAT_ID below with a real value to actually change anything)
gcloud run services update %SUMMARIZER_SERVICE_NAME% ^
  --region=%REGION% ^
  --update-env-vars=TELEGRAM_CHAT_ID=NEW_CHAT_ID

echo.
echo == updating news-fetcher's RSS_FEED_URL live ==
gcloud functions deploy %FETCHER_FUNCTION_NAME% ^
  --gen2 --region=%REGION% ^
  --update-env-vars=RSS_FEED_URL=https://techcrunch.com/tag/cloud-computing/feed/

echo.
echo Notice: the Cloud Run update above needed no "docker build", no
echo "docker push", no new image - just new configuration, live within
echo seconds. The Cloud Function deploy above this line is DIFFERENT: gcloud
echo functions deploy rebuilds via Cloud Build every time, even for an
echo env-var-only change like this one - the env var still takes effect
echo with no code change, it just isn't a zero-build operation the way the
echo Cloud Run update is.

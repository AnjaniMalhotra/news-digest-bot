@echo off
REM Topic 3 - Cloud Scheduler: a daily job targeting topic 1's Pub/Sub topic.
REM Requires: 01_pubsub_setup.bat already run (reuses that topic entirely).

echo == creating the scheduled job (daily at 8 AM IST) ==
gcloud scheduler jobs create pubsub morning-digest-job ^
  --schedule="0 8 * * *" ^
  --topic=%TOPIC_NAME% ^
  --message-body="{\"feed_url\": \"https://techcrunch.com/tag/artificial-intelligence/feed/\"}" ^
  --time-zone="Asia/Kolkata" ^
  --location=%REGION%

echo.
echo == triggering it manually right now, instead of waiting until tomorrow ==
gcloud scheduler jobs run morning-digest-job --location=%REGION%

echo.
echo Check your Telegram in a few seconds.

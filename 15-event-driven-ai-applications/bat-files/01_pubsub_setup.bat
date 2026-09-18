@echo off
REM Topic 1 - Pub/Sub: create the topic, deploy digest-worker-pubsub, test it.
REM Requires: 00_setup_vars.bat + 00a_initial_setup.bat already run.

echo == creating the Pub/Sub topic ==
gcloud pubsub topics create %TOPIC_NAME%

echo == deploying digest-worker-pubsub ==
gcloud functions deploy digest-worker-pubsub ^
  --gen2 --runtime=python311 --region=%REGION% --source=digest_worker ^
  --entry-point=on_pubsub_message ^
  --trigger-topic=%TOPIC_NAME% ^
  --service-account=%WORKER_SA_EMAIL% ^
  --set-env-vars=PROJECT_ID=%PROJECT_ID%,LOCATION=%LOCATION%,TELEGRAM_CHAT_ID=%TELEGRAM_CHAT_ID%,SECRET_NAME=%SECRET_NAME%

echo == letting the auto-created Eventarc/Pub/Sub push subscription invoke this function ==
echo (it authenticates AS %WORKER_SA_NAME% itself - without this grant, every
echo  push silently fails with "IAM principal lacks run.routes.invoke permission")
gcloud run services add-iam-policy-binding digest-worker-pubsub ^
  --region=%REGION% ^
  --member="serviceAccount:%WORKER_SA_EMAIL%" ^
  --role="roles/run.invoker"

echo.
echo == publishing a test message ==
gcloud pubsub topics publish %TOPIC_NAME% --message="{\"feed_url\": \"https://techcrunch.com/tag/artificial-intelligence/feed/\"}"

echo.
echo Check your Telegram in a few seconds. Also check logs if nothing arrives:
echo   gcloud functions logs read digest-worker-pubsub --region=%REGION% --gen2 --limit=20

@echo off
REM Topic 2 - Eventarc: create the bucket, deploy digest-worker-storage, test it.
REM Requires: 00_setup_vars.bat + 00a_initial_setup.bat already run.

echo == creating the feeds bucket ==
REM Bucket names are globally unique across ALL of GCP - if %FEEDS_BUCKET_NAME%
REM is taken, pick a different one (e.g. append your project ID).
gcloud storage buckets create gs://%FEEDS_BUCKET_NAME% --location=%REGION%

echo == letting the Cloud Storage service agent notify Eventarc for this project ==
echo (one-time per project - without it, the trigger deploy below fails with
echo  "Failed to update storage bucket metadata")
for /f %%i in ('gcloud storage service-agent --project=%PROJECT_ID%') do set GCS_AGENT=%%i
gcloud projects add-iam-policy-binding %PROJECT_ID% ^
  --member="serviceAccount:%GCS_AGENT%" ^
  --role="roles/pubsub.publisher"

echo == letting the trigger's own service account receive Eventarc events ==
echo (must be granted BEFORE the deploy below - the deploy itself fails with
echo  "Permission eventarc.events.receiveEvent denied" without it)
gcloud projects add-iam-policy-binding %PROJECT_ID% ^
  --member="serviceAccount:%WORKER_SA_EMAIL%" ^
  --role="roles/eventarc.eventReceiver"

echo == deploying digest-worker-storage (Eventarc-triggered) ==
gcloud functions deploy digest-worker-storage ^
  --gen2 --runtime=python311 --region=%REGION% --source=digest_worker ^
  --entry-point=on_storage_event ^
  --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" ^
  --trigger-event-filters="bucket=%FEEDS_BUCKET_NAME%" ^
  --service-account=%WORKER_SA_EMAIL% ^
  --set-env-vars=PROJECT_ID=%PROJECT_ID%,LOCATION=%LOCATION%,TELEGRAM_CHAT_ID=%TELEGRAM_CHAT_ID%,SECRET_NAME=%SECRET_NAME%

echo == letting the trigger's push subscription invoke this function (same pattern as topic 1) ==
gcloud run services add-iam-policy-binding digest-worker-storage ^
  --region=%REGION% ^
  --member="serviceAccount:%WORKER_SA_EMAIL%" ^
  --role="roles/run.invoker"

echo == letting the worker actually READ files from the bucket it's triggered by ==
echo (separate from receiving the event notification itself)
gcloud storage buckets add-iam-policy-binding gs://%FEEDS_BUCKET_NAME% ^
  --member="serviceAccount:%WORKER_SA_EMAIL%" ^
  --role="roles/storage.objectViewer"

echo.
echo == uploading a test feeds.txt ==
echo https://techcrunch.com/tag/artificial-intelligence/feed/ > feeds.txt
gcloud storage cp feeds.txt gs://%FEEDS_BUCKET_NAME%/feeds.txt

echo.
echo Check your Telegram in a few seconds - no direct call was made, the
echo upload itself triggered everything. Check logs if nothing arrives:
echo   gcloud functions logs read digest-worker-storage --region=%REGION% --gen2 --limit=20

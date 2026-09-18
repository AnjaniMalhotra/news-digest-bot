@echo off
REM Tears down everything this module created.
REM Requires: 00_setup_vars.bat already run in this same window.
REM Nothing here is billable beyond the Always Free tier, but this is good
REM hygiene - run it when you're done with the module.

echo == deleting the API Gateway gateway, config, and API ==
gcloud api-gateway gateways delete %GATEWAY_ID% --location=%REGION% --quiet
gcloud api-gateway api-configs delete %API_CONFIG_ID% --api=%API_ID% --quiet
gcloud api-gateway apis delete %API_ID% --quiet

echo == deleting the Cloud Tasks queue ==
gcloud tasks queues delete %QUEUE_NAME% --location=%REGION% --quiet

echo == deleting all three digest-worker functions ==
gcloud functions delete digest-worker-pubsub --region=%REGION% --gen2 --quiet
gcloud functions delete digest-worker-storage --region=%REGION% --gen2 --quiet
gcloud functions delete digest-worker-http --region=%REGION% --gen2 --quiet

echo == deleting the Cloud Scheduler job ==
gcloud scheduler jobs delete morning-digest-job --location=%REGION% --quiet

echo == deleting the Pub/Sub topic ==
gcloud pubsub topics delete %TOPIC_NAME% --quiet

echo == deleting the feeds bucket ==
gcloud storage rm -r gs://%FEEDS_BUCKET_NAME% --quiet

echo == deleting the secret ==
gcloud secrets delete %SECRET_NAME% --quiet

echo == deleting both service accounts ==
gcloud iam service-accounts delete %WORKER_SA_EMAIL% --quiet
gcloud iam service-accounts delete %TASKS_SA_EMAIL% --quiet

echo.
echo All done.

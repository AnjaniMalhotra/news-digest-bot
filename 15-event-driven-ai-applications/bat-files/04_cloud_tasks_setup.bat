@echo off
REM Topic 4 - Cloud Tasks: create the queue, deploy digest-worker-http,
REM grant the tasks dispatcher SA permission to invoke it.
REM Requires: 00_setup_vars.bat + 00a_initial_setup.bat already run.

echo == creating the Cloud Tasks queue ==
gcloud tasks queues create %QUEUE_NAME% --location=%REGION%

echo == deploying digest-worker-http (locked down) ==
gcloud functions deploy digest-worker-http ^
  --gen2 --runtime=python311 --region=%REGION% --source=digest_worker ^
  --entry-point=on_http_request ^
  --trigger-http --no-allow-unauthenticated ^
  --service-account=%WORKER_SA_EMAIL% ^
  --set-env-vars=PROJECT_ID=%PROJECT_ID%,LOCATION=%LOCATION%,TELEGRAM_CHAT_ID=%TELEGRAM_CHAT_ID%,SECRET_NAME=%SECRET_NAME%

echo == letting the tasks dispatcher SA invoke it ==
gcloud run services add-iam-policy-binding digest-worker-http ^
  --region=%REGION% ^
  --member="serviceAccount:%TASKS_SA_EMAIL%" ^
  --role="roles/run.invoker"

echo == letting Cloud Tasks itself mint OIDC tokens AS the dispatcher SA ==
echo (without this, run.invoker above is not enough - every dispatch fails
echo  with "IAM principal lacks run.routes.invoke permission" because Cloud
echo  Tasks was never able to actually create a valid token as %TASKS_SA_NAME%
echo  in the first place, so Cloud Run sees an unauthenticated request)
for /f %%i in ('gcloud projects describe %PROJECT_ID% --format="value(projectNumber)"') do set PROJECT_NUMBER=%%i
gcloud iam service-accounts add-iam-policy-binding %TASKS_SA_EMAIL% ^
  --member="serviceAccount:service-%PROJECT_NUMBER%@gcp-sa-cloudtasks.iam.gserviceaccount.com" ^
  --role="roles/iam.serviceAccountTokenCreator"

echo.
echo == getting the function's URL for the Python script below ==
gcloud functions describe digest-worker-http --region=%REGION% --gen2 --format="value(serviceConfig.uri)"

echo.
echo Copy that URL into .env as WORKER_HTTP_URL, then run:
echo   python 04_create_tasks.py

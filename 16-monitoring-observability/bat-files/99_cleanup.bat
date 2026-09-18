@echo off
REM Tears down everything this module created.
REM Requires: 00_setup_vars.bat already run in this same window.

echo == deleting the dashboard ==
echo (find its ID first if needed: gcloud monitoring dashboards list)
echo   gcloud monitoring dashboards delete DASHBOARD_ID --quiet

echo == deleting the alert policy ==
echo (find its ID first if needed: gcloud alpha monitoring policies list)
echo   gcloud alpha monitoring policies delete POLICY_ID --quiet

echo == deleting the notification channel ==
echo   gcloud alpha monitoring channels delete CHANNEL_ID --quiet

echo == deleting the log-based metric ==
gcloud logging metrics delete digest_simulated_errors --quiet

echo == deleting the Cloud Run service ==
gcloud run services delete %SERVICE_NAME% --region=%REGION% --quiet

echo == deleting the secret ==
gcloud secrets delete %SECRET_NAME% --quiet

echo == deleting the service account ==
gcloud iam service-accounts delete %WORKER_SA_EMAIL% --quiet

echo.
echo All done. Note: the dashboard, policy, and channel IDs above need to be
echo filled in manually since gcloud doesn't let you delete them by display
echo name - list them first if you don't have the IDs handy.

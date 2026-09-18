@echo off
REM Tears down everything this module created.
REM Requires: 00_setup_vars.bat already run in this same window.
REM Nothing here is billable beyond the Always Free tier, but this is good
REM hygiene to demonstrate - run it when you're done with the module.

echo == deleting the Cloud Run service ==
gcloud run services delete %SUMMARIZER_SERVICE_NAME% --region=%REGION% --quiet

echo == deleting the Cloud Function ==
gcloud functions delete %FETCHER_FUNCTION_NAME% --region=%REGION% --gen2 --quiet

echo == deleting the Artifact Registry repository (and every image in it) ==
gcloud artifacts repositories delete %REPO_NAME% --location=%REGION% --quiet

echo == deleting the secret ==
gcloud secrets delete %SECRET_NAME% --quiet

echo == deleting both service accounts ==
gcloud iam service-accounts delete %SUMMARIZER_SA_EMAIL% --quiet
gcloud iam service-accounts delete %FETCHER_SA_EMAIL% --quiet

echo.
echo All done.

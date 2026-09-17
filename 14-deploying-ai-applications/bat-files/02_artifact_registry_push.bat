@echo off
REM Topic 2 - Push the news-summarizer image to Artifact Registry.
REM Requires: 00_setup_vars.bat already run, image already built (topic 1).

echo == creating the Artifact Registry repository (skip if it already exists) ==
gcloud artifacts repositories create %REPO_NAME% ^
  --repository-format=docker ^
  --location=%REGION% ^
  --description="Deploying AI Applications module"

echo == letting Docker authenticate to Artifact Registry ==
gcloud auth configure-docker %REGION%-docker.pkg.dev --quiet

echo == tagging the local image with the full Artifact Registry path ==
docker tag news-summarizer-local %REGION%-docker.pkg.dev/%PROJECT_ID%/%REPO_NAME%/news-summarizer:v1

echo == pushing ==
docker push %REGION%-docker.pkg.dev/%PROJECT_ID%/%REPO_NAME%/news-summarizer:v1

echo == confirming it's there ==
gcloud artifacts docker images list %REGION%-docker.pkg.dev/%PROJECT_ID%/%REPO_NAME%

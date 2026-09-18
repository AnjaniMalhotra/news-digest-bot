@echo off
REM Topic 2 - Cloud Monitoring: generate some traffic, then look at the
REM built-in metrics that were collected automatically.
REM Requires: 01_deploy_and_view_logging.bat already run.

echo == sending a few normal requests to generate data ==
echo Run these manually, replacing SERVICE_URL with your real service URL:
echo   curl SERVICE_URL
echo   curl SERVICE_URL
echo   curl SERVICE_URL

echo.
echo == listing available Cloud Run metric types (no code was written for any of these) ==
REM `gcloud monitoring metrics-descriptors list` does not exist in current
REM gcloud SDK versions - use the underlying REST API directly instead.
for /f %%i in ('gcloud auth print-access-token') do set TOKEN=%%i
curl -s -H "Authorization: Bearer %TOKEN%" "https://monitoring.googleapis.com/v3/projects/%PROJECT_ID%/metricDescriptors?filter=metric.type%%3Dstarts_with(%%22run.googleapis.com%%22)&pageSize=10"

echo.
echo Now open Console -^> Monitoring -^> Metrics Explorer, resource type
echo "Cloud Run Revision", and chart Request Count or Request Latencies.

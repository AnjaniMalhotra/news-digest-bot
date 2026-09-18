@echo off
REM Topic 5 - Metrics: view the custom metric the app writes itself.
REM Requires: a few normal (non-error) requests already sent, so there's
REM at least one data point.

echo == sending a normal request to generate a data point ==
echo Run this manually, replacing SERVICE_URL with your real service URL:
echo   curl SERVICE_URL

echo.
echo == querying the custom metric directly ==
REM `gcloud monitoring time-series list` does not exist in current gcloud
REM SDK versions - use the underlying REST API directly instead.
for /f %%i in ('gcloud auth print-access-token') do set TOKEN=%%i
curl -s -H "Authorization: Bearer %TOKEN%" "https://monitoring.googleapis.com/v3/projects/%PROJECT_ID%/timeSeries?filter=metric.type%%3D%%22custom.googleapis.com%%2Fdigest%%2Fheadlines_processed%%22&interval.startTime=2026-01-01T00:00:00Z&interval.endTime=2026-12-31T00:00:00Z"

echo.
echo Also viewable in Console -^> Monitoring -^> Metrics Explorer, searching
echo for "headlines_processed" - notice it's NOT in topic 2's built-in list.

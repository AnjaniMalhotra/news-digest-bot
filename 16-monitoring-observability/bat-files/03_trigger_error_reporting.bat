@echo off
REM Topic 3 - Error Reporting: trigger a real, unhandled exception on purpose.
REM Requires: 01_deploy_and_view_logging.bat already run.

echo == triggering the simulated error (a real 500, on purpose) ==
echo Run this manually, replacing SERVICE_URL with your real service URL:
echo   curl "SERVICE_URL/?simulate_error=true"

echo.
echo == checking recent ERROR-severity logs ==
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=%SERVICE_NAME% AND severity=ERROR" --limit=10

echo.
echo Now open Console -^> Error Reporting - wait a few seconds after the
echo curl call if it's not there yet. You should see a grouped error with
echo the real Python stack trace.

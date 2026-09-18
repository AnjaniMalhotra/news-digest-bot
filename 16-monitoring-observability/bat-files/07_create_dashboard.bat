@echo off
REM Topic 7 - Dashboards: one view combining every signal from this module.
REM Requires: topics 1-5 already demoed at least once, so every tile has data.

echo == deploying the dashboard ==
gcloud monitoring dashboards create --config-from-file=07_dashboard.json

echo.
echo == generating a mix of traffic so every tile has something to show ==
echo Run these manually, replacing SERVICE_URL with your real service URL:
echo   curl SERVICE_URL
echo   curl "SERVICE_URL/?simulate_error=true"
echo   curl "SERVICE_URL/?simulate_slow=true"

echo.
echo Open Console -^> Monitoring -^> Dashboards -^> "Digest Worker Health".
echo Give it a minute, then refresh - all four tiles should show real data.

@echo off
REM Topic 4 - Cloud Trace: trigger deliberate slowness, then read the waterfall.
REM Requires: 01_deploy_and_view_logging.bat already run.

echo == triggering the simulated slow path (~8 seconds, on purpose) ==
echo Run this manually, replacing SERVICE_URL with your real service URL:
echo   curl "SERVICE_URL/?simulate_slow=true"

echo.
echo == for comparison, a normal request ==
echo   curl SERVICE_URL

echo.
echo Now open Console -^> Trace -^> Trace List. Open the recent traces and
echo compare: the slow one's "summarize_headlines" span should dominate
echo the waterfall; the normal one's shouldn't.

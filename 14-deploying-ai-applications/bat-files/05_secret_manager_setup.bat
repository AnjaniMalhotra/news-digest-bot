@echo off
REM Topic 5 - Create the Telegram bot token secret.
REM Requires: 00_setup_vars.bat already run, and TELEGRAM_BOT_TOKEN set to
REM your REAL token (see topic 5's doc for how to get one from @BotFather).

echo == creating the secret container ==
gcloud secrets create %SECRET_NAME% --replication-policy=automatic

echo == adding the real token as its first version ==
echo %TELEGRAM_BOT_TOKEN% | gcloud secrets versions add %SECRET_NAME% --data-file=-

echo == confirming a version exists (without printing the value) ==
gcloud secrets versions list %SECRET_NAME%

echo.
echo Retry topic 3's curl test now - the error should CHANGE from
echo "secret not found" to "permission denied". That's expected -
echo access isn't granted yet. That's topic 6.

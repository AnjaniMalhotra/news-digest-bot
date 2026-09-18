@echo off
REM Shared variables for every .bat script in this module.
REM Run this FIRST, in the SAME Command Prompt window you'll run the rest in.

set PROJECT_ID=agentic-ai-capstone-1
set REGION=us-central1
set LOCATION=us-central1

set SERVICE_NAME=digest-worker-observable
set WORKER_SA_NAME=digest-observable-sa
set WORKER_SA_EMAIL=%WORKER_SA_NAME%@%PROJECT_ID%.iam.gserviceaccount.com

set SECRET_NAME=telegram-bot-token-observability

REM DUMMY VALUES - replace with your real Telegram bot details
set TELEGRAM_BOT_TOKEN=your-telegram-bot-token-here
set TELEGRAM_CHAT_ID=your-telegram-chat-id-here

REM DUMMY VALUE - replace with a real email for topic 6's alert
set NOTIFICATION_EMAIL=your-email@example.com

REM Filled in AFTER the initial deploy - paste the printed Cloud Run URL here
set SERVICE_URL=https://REPLACE-ME-AFTER-DEPLOY.run.app

echo Loaded vars: PROJECT_ID=%PROJECT_ID%, REGION=%REGION%

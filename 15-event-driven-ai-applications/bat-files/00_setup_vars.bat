@echo off
REM Shared variables for every .bat script in this module.
REM Run this FIRST, in the SAME Command Prompt window you'll run the rest in.

set PROJECT_ID=agentic-ai-capstone-1
set REGION=us-central1
set LOCATION=us-central1

set TOPIC_NAME=digest-requests
set FEEDS_BUCKET_NAME=digest-feeds-bucket
set QUEUE_NAME=digest-fetch-queue

set WORKER_SA_NAME=digest-worker-sa
set TASKS_SA_NAME=digest-tasks-sa
set WORKER_SA_EMAIL=%WORKER_SA_NAME%@%PROJECT_ID%.iam.gserviceaccount.com
set TASKS_SA_EMAIL=%TASKS_SA_NAME%@%PROJECT_ID%.iam.gserviceaccount.com

set SECRET_NAME=telegram-bot-token-eventdriven

REM DUMMY VALUES - replace with your real Telegram bot details
set TELEGRAM_BOT_TOKEN=your-telegram-bot-token-here
set TELEGRAM_CHAT_ID=your-telegram-chat-id-here

REM Filled in AFTER topic 4's function deploy - paste the printed URL here
set WORKER_HTTP_URL=https://REPLACE-ME-AFTER-TOPIC-4.run.app

set API_ID=digest-api
set API_CONFIG_ID=digest-config
set GATEWAY_ID=digest-gateway

echo Loaded vars: PROJECT_ID=%PROJECT_ID%, REGION=%REGION%

"""Topic 4 — Cloud Tasks: enqueue one task per feed.

Each task carries an OIDC token scoped to digest-worker-http's URL — the
same identity-token pattern from Module 14, just attached per-task instead
of computed manually before each call.

Requires: 04_cloud_tasks_setup.bat already run, WORKER_HTTP_URL filled in
.env with the real function URL it printed.

Run with: python 04_create_tasks.py
"""

import json
import os

from dotenv import load_dotenv
from google.cloud import tasks_v2

load_dotenv()

PROJECT_ID = os.environ["PROJECT_ID"]
REGION = os.environ["REGION"]
QUEUE_NAME = os.environ["QUEUE_NAME"]
WORKER_HTTP_URL = os.environ["WORKER_HTTP_URL"]
TASKS_SA_EMAIL = f"{os.environ['TASKS_SA_NAME']}@{PROJECT_ID}.iam.gserviceaccount.com"

# NOT Google News /rss/search URLs - Google blocks that endpoint's traffic
# from Google Cloud's own egress IPs with a 503 bot-detection page (found
# and confirmed in Module 14 - digest-worker-http runs on Cloud Functions,
# a GCP-hosted caller, so it hits the same block).
FEEDS_TO_PROCESS = [
    "https://techcrunch.com/tag/artificial-intelligence/feed/",
    "https://techcrunch.com/tag/google/feed/",
    "https://techcrunch.com/tag/climate/feed/",
]


def create_task(feed_url: str):
    client = tasks_v2.CloudTasksClient()
    parent = client.queue_path(PROJECT_ID, REGION, QUEUE_NAME)

    task = {
        "http_request": {
            "http_method": tasks_v2.HttpMethod.POST,
            "url": WORKER_HTTP_URL,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"feed_url": feed_url}).encode(),
            "oidc_token": {
                "service_account_email": TASKS_SA_EMAIL,
                "audience": WORKER_HTTP_URL,
            },
        }
    }

    response = client.create_task(request={"parent": parent, "task": task})
    print(f"Created task for {feed_url}: {response.name}")


if __name__ == "__main__":
    for feed in FEEDS_TO_PROCESS:
        create_task(feed)
    print(f"\n{len(FEEDS_TO_PROCESS)} tasks enqueued. Check your Telegram over the next minute.")

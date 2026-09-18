"""digest-worker — one small worker, deployed three different ways across
this module's topics. Fetches a news feed, summarizes it with Vertex AI
Gemini, sends the result to Telegram. The Telegram token comes from Secret
Manager, same pattern as Module 14 (not re-explained here in depth).

Three entry points, three trigger types, one shared core function:
  - on_pubsub_message  -> Pub/Sub trigger (topic 1), also used by topic 3
  - on_storage_event   -> Eventarc / Cloud Storage trigger (topic 2)
  - on_http_request    -> HTTP trigger (topics 4 and 5)
"""

import base64
import json
import os

import feedparser
import functions_framework
import requests
from cloudevents.http import CloudEvent
from google import genai
from google.cloud import secretmanager, storage

PROJECT_ID = os.environ["PROJECT_ID"]
LOCATION = os.environ.get("LOCATION", "us-central1")
TELEGRAM_CHAT_ID = os.environ["TELEGRAM_CHAT_ID"]
SECRET_NAME = os.environ["SECRET_NAME"]

MODEL_FLASH = "gemini-2.5-flash"  # verify still current/GA against Vertex AI's model docs
# NOT a Google News /rss/search URL - Google blocks that endpoint's traffic
# from Google Cloud's own egress IPs with a 503 bot-detection page (found
# and confirmed in Module 14; same underlying GCP-hosted-caller issue here).
DEFAULT_FEED_URL = "https://techcrunch.com/tag/artificial-intelligence/feed/"

genai_client = genai.Client(vertexai=True, project=PROJECT_ID, location=LOCATION)


def get_secret(secret_id: str) -> str:
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(name=name)
    return response.payload.data.decode("UTF-8")


def run_digest(feed_url: str) -> dict:
    """The shared core: fetch -> summarize -> send to Telegram."""
    feed = feedparser.parse(feed_url)
    headlines = [entry.title for entry in feed.entries[:10]]

    if not headlines:
        return {"status": "no headlines found", "feed_url": feed_url}

    headlines_text = "\n".join(f"- {h}" for h in headlines)
    prompt = (
        "Summarize today's top news in 5 short, friendly bullet points, "
        "based only on these headlines:\n\n" + headlines_text
    )
    response = genai_client.models.generate_content(model=MODEL_FLASH, contents=prompt)
    summary = response.text

    bot_token = get_secret(SECRET_NAME)
    telegram_url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    telegram_response = requests.post(
        telegram_url,
        json={"chat_id": TELEGRAM_CHAT_ID, "text": f"\U0001F4F0 Your Daily Digest\n\n{summary}"},
        timeout=10,
    )

    return {"status": "sent", "summary": summary, "telegram_status": telegram_response.status_code}


# ---------------------------------------------------------------
# Topic 1 (and 3) — Pub/Sub trigger
# ---------------------------------------------------------------
@functions_framework.cloud_event
def on_pubsub_message(cloud_event: CloudEvent) -> None:
    message_data = base64.b64decode(cloud_event.data["message"]["data"]).decode("utf-8")
    payload = json.loads(message_data) if message_data else {}
    feed_url = payload.get("feed_url", DEFAULT_FEED_URL)
    result = run_digest(feed_url)
    print(result)


# ---------------------------------------------------------------
# Topic 2 — Eventarc / Cloud Storage trigger
# ---------------------------------------------------------------
@functions_framework.cloud_event
def on_storage_event(cloud_event: CloudEvent) -> None:
    data = cloud_event.data
    bucket_name = data["bucket"]
    file_name = data["name"]

    storage_client = storage.Client(project=PROJECT_ID)
    blob = storage_client.bucket(bucket_name).blob(file_name)
    contents = blob.download_as_text()

    feed_urls = [line.strip() for line in contents.splitlines() if line.strip()]
    if not feed_urls:
        feed_urls = [DEFAULT_FEED_URL]

    for feed_url in feed_urls:
        result = run_digest(feed_url)
        print(result)


# ---------------------------------------------------------------
# Topics 4 and 5 — HTTP trigger (Cloud Tasks dispatch, API Gateway front door)
# ---------------------------------------------------------------
@functions_framework.http
def on_http_request(request):
    data = request.get_json(silent=True) or {}
    feed_url = data.get("feed_url", DEFAULT_FEED_URL)
    result = run_digest(feed_url)
    return result

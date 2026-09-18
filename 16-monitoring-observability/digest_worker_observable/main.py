"""digest-worker-observable — a Cloud Run service, rebuilt fresh for this
module (no imports from the Module 14 or 15 branches, per the isolation rule).

Same job as before (fetch a feed, summarize with Gemini, send to
Telegram) — but instrumented with structured logging, custom trace spans,
and a custom metric, plus two switches that deliberately break it:

    ?simulate_error=true   -> raises a real, unhandled exception
    ?simulate_slow=true    -> deliberately takes ~8 seconds

Breaking it on purpose is the point of this module: prove the
monitoring actually catches problems before trusting it in production.
"""

import logging
import os
import time

import feedparser
import requests
from flask import Flask, jsonify, request
from google import genai
from google.cloud import logging as cloud_logging
from google.cloud import monitoring_v3
from google.cloud import secretmanager
from opentelemetry import trace
from opentelemetry.exporter.cloud_trace import CloudTraceSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# --- Topic 1: Cloud Logging - route standard `logging` calls there ---
cloud_logging.Client().setup_logging()

# --- Topic 4: Cloud Trace - custom spans via OpenTelemetry ---
trace.set_tracer_provider(TracerProvider())
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(CloudTraceSpanExporter()))
tracer = trace.get_tracer(__name__)

app = Flask(__name__)

PROJECT_ID = os.environ["PROJECT_ID"]
LOCATION = os.environ.get("LOCATION", "us-central1")
TELEGRAM_CHAT_ID = os.environ["TELEGRAM_CHAT_ID"]
SECRET_NAME = os.environ["SECRET_NAME"]
MODEL_FLASH = "gemini-2.5-flash"  # verify still current/GA against Vertex AI's model docs
# NOT a Google News /rss/search URL - Google blocks that endpoint's traffic
# from Google Cloud's own egress IPs with a 503 bot-detection page (found
# and confirmed in Modules 14/15; same underlying GCP-hosted-caller issue).
DEFAULT_FEED_URL = "https://techcrunch.com/tag/artificial-intelligence/feed/"

genai_client = genai.Client(vertexai=True, project=PROJECT_ID, location=LOCATION)
monitoring_client = monitoring_v3.MetricServiceClient()


def get_secret(secret_id: str) -> str:
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/latest"
    return client.access_secret_version(name=name).payload.data.decode("UTF-8")


def write_custom_metric(headline_count: int) -> None:
    """Topic 5 - a metric only this app knows how to define."""
    series = monitoring_v3.TimeSeries()
    series.metric.type = "custom.googleapis.com/digest/headlines_processed"
    series.resource.type = "global"
    series.resource.labels["project_id"] = PROJECT_ID

    now = time.time()
    seconds = int(now)
    nanos = int((now - seconds) * 10**9)
    # The client library's well-known Timestamp field (end_time) isn't
    # mutable in place like a plain submessage - it must be constructed
    # and assigned as a whole, not field-by-field.
    interval = monitoring_v3.TimeInterval({"end_time": {"seconds": seconds, "nanos": nanos}})
    point = monitoring_v3.Point({"interval": interval, "value": {"int64_value": headline_count}})
    series.points = [point]

    monitoring_client.create_time_series(name=f"projects/{PROJECT_ID}", time_series=[series])


def fetch_headlines(feed_url: str) -> list[str]:
    with tracer.start_as_current_span("fetch_headlines") as span:
        span.set_attribute("feed_url", feed_url)
        feed = feedparser.parse(feed_url)
        headlines = [entry.title for entry in feed.entries[:10]]
        span.set_attribute("headline_count", len(headlines))
        return headlines


def summarize_headlines(headlines: list[str], simulate_slow: bool) -> str:
    with tracer.start_as_current_span("summarize_headlines") as span:
        span.set_attribute("simulated_slowness", simulate_slow)
        if simulate_slow:
            time.sleep(8)  # pretend the model call is slow, ON PURPOSE - see topic 4

        headlines_text = "\n".join(f"- {h}" for h in headlines)
        prompt = f"Summarize today's top news in 5 short bullet points:\n\n{headlines_text}"
        response = genai_client.models.generate_content(model=MODEL_FLASH, contents=prompt)
        return response.text


def send_to_telegram(summary: str) -> int:
    with tracer.start_as_current_span("send_to_telegram"):
        bot_token = get_secret(SECRET_NAME)
        telegram_url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        response = requests.post(
            telegram_url,
            json={"chat_id": TELEGRAM_CHAT_ID, "text": f"\U0001F4F0 Your Daily Digest\n\n{summary}"},
            timeout=10,
        )
        return response.status_code


@app.route("/", methods=["GET", "POST"])
def run_digest():
    simulate_error = request.args.get("simulate_error", "false").lower() == "true"
    simulate_slow = request.args.get("simulate_slow", "false").lower() == "true"
    feed_url = request.args.get("feed_url", DEFAULT_FEED_URL)

    with tracer.start_as_current_span("run_digest") as span:
        span.set_attribute("simulate_error", simulate_error)
        span.set_attribute("simulate_slow", simulate_slow)
        span.set_attribute("feed_url", feed_url)

        logging.info(
            "digest run started",
            extra={"json_fields": {"feed_url": feed_url, "simulate_error": simulate_error, "simulate_slow": simulate_slow}},
        )

        if simulate_error:
            logging.error(
                "simulated failure triggered on purpose",
                extra={"json_fields": {"feed_url": feed_url}},
            )
            # Deliberately unhandled - topic 3 (Error Reporting) needs a real,
            # uncaught exception to demonstrate automatic detection.
            raise RuntimeError("Simulated failure - this is intentional, see topic 3")

        headlines = fetch_headlines(feed_url)
        if not headlines:
            logging.warning("no headlines found", extra={"json_fields": {"feed_url": feed_url}})
            return jsonify({"status": "no headlines found", "feed_url": feed_url}), 200

        summary = summarize_headlines(headlines, simulate_slow)
        telegram_status = send_to_telegram(summary)
        write_custom_metric(len(headlines))

        logging.info(
            "digest run completed",
            extra={"json_fields": {
                "feed_url": feed_url,
                "headline_count": len(headlines),
                "telegram_status": telegram_status,
            }},
        )

        return jsonify({"status": "sent", "headline_count": len(headlines), "summary": summary})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))

"""news-summarizer — a Cloud Run service.

Receives a list of news headlines, summarizes them with Vertex AI Gemini,
and sends the result to a personal Telegram chat. The Telegram bot token
comes from Secret Manager (topic 5) — never hardcoded, never a plain env var.
"""

import os

import requests
from flask import Flask, jsonify, request
from google import genai
from google.cloud import secretmanager

app = Flask(__name__)

PROJECT_ID = os.environ["PROJECT_ID"]
LOCATION = os.environ.get("LOCATION", "us-central1")
TELEGRAM_CHAT_ID = os.environ["TELEGRAM_CHAT_ID"]
SECRET_NAME = os.environ["SECRET_NAME"]

MODEL_FLASH = "gemini-2.5-flash"  # verify still current/GA against Vertex AI's model docs

genai_client = genai.Client(vertexai=True, project=PROJECT_ID, location=LOCATION)


def get_secret(secret_id: str) -> str:
    """Read the latest version of a secret from Secret Manager."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/latest"
    response = client.access_secret_version(name=name)
    return response.payload.data.decode("UTF-8")


@app.route("/", methods=["POST"])
def summarize_and_send():
    data = request.get_json(silent=True) or {}
    headlines = data.get("headlines", [])

    if not headlines:
        return jsonify({"error": "no headlines provided"}), 400

    headlines_text = "\n".join(f"- {h}" for h in headlines)
    prompt = (
        "Summarize today's top news in 5 short, friendly bullet points, "
        "based only on these headlines:\n\n" + headlines_text
    )

    response = genai_client.models.generate_content(model=MODEL_FLASH, contents=prompt)
    summary = response.text

    try:
        bot_token = get_secret(SECRET_NAME)
    except Exception as e:
        # Deliberately surfaced, not swallowed - topics 3, 5, and 6 rely on
        # seeing this exact failure mode at different points in the module.
        return jsonify({"error": f"could not read secret: {e}"}), 500

    telegram_url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    telegram_response = requests.post(
        telegram_url,
        json={"chat_id": TELEGRAM_CHAT_ID, "text": f"\U0001F4F0 Your Daily Digest\n\n{summary}"},
        timeout=10,
    )

    return jsonify({
        "status": "sent",
        "summary": summary,
        "telegram_status": telegram_response.status_code,
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))

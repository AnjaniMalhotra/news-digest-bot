@echo off
REM Topic 1 - Build the news-summarizer image and run it locally.
REM Requires: Docker Desktop running, 00_setup_vars.bat already run,
REM and `gcloud auth application-default login` already done on this machine.

cd news_summarizer

echo == building the image ==
docker build -t news-summarizer-local .

echo.
echo == running it locally (mounts your ADC credentials so it can call ==
echo == Vertex AI / Secret Manager, same as it will on Cloud Run)      ==
echo Press Ctrl+C to stop once you're done testing.
echo.
docker run --rm -p 8080:8080 ^
  --env-file ..\.env ^
  -e PORT=8080 ^
  -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/keys/adc.json ^
  -v "%APPDATA%\gcloud\application_default_credentials.json:/tmp/keys/adc.json:ro" ^
  news-summarizer-local

REM In a SECOND Command Prompt window, while this is running, test it:
REM   curl -X POST -H "Content-Type: application/json" -d "{\"headlines\": [\"Test headline one\", \"Test headline two\"]}" http://localhost:8080/

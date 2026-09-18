FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# gunicorn, not Flask's dev server - this is what actually runs in production
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 60 main:app

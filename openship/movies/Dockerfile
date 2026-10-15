# syntax=docker/dockerfile:1
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

RUN groupadd --system asterion \
    && useradd --system --gid asterion --home-dir /app asterion

COPY services/movies/requirements.txt ./
RUN pip install --no-cache-dir --requirement requirements.txt

COPY services/movies/app.py services/movies/playback.py services/movies/soap2day.py services/movies/db.py services/movies/genre_catalog.py services/movies/schema.sql ./

USER asterion

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ['PORT'] + '/api/health', timeout=3)"

CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --threads 8 --worker-class gthread --timeout 120 --graceful-timeout 30 --no-control-socket --access-logfile - --error-logfile - app:app"]

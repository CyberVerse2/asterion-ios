FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

RUN groupadd --system asterion \
    && useradd --system --gid asterion --home-dir /app asterion

COPY requirements.txt ./
RUN pip install --no-cache-dir --requirement requirements.txt

COPY app.py soap2day.py db.py schema.sql ./

USER asterion

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ['PORT'] + '/api/health', timeout=3)"

CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --threads 4 --worker-class gthread --timeout 120 --graceful-timeout 30 --no-control-socket --access-logfile - --error-logfile - app:app"]

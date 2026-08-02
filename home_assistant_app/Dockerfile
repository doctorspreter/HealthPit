FROM python:3.12-slim

ARG BUILD_VERSION="dev"
LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="aarch64|amd64" \
    org.opencontainers.image.title="Healthpit Bridge Home Assistant App" \
    org.opencontainers.image.description="Healthpit bridge with Home Assistant Ingress configuration" \
    org.opencontainers.image.source="https://github.com/doctorspreter/healthpit" \
    org.opencontainers.image.licenses="Apache-2.0"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app

WORKDIR /app

COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY run.sh /run.sh
RUN chmod 0755 /run.sh && mkdir -p /data/db

EXPOSE 8088
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8088/health', timeout=5).read()"

CMD ["/run.sh"]

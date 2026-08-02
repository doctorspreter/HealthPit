#!/usr/bin/env bash
set -Eeuo pipefail

cd /app
python -m app.bootstrap
# shellcheck disable=SC1091
source /data/runtime.env

exec uvicorn app.main:app --host 0.0.0.0 --port 8088 --log-level "${LOG_LEVEL}"

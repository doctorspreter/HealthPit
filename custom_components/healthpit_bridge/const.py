"""Constants for the Healthpit Bridge integration."""

from __future__ import annotations

DOMAIN = "healthpit_bridge"

CONF_HOST = "host"
CONF_PORT = "port"
CONF_USERNAME = "username"
CONF_TOKEN = "token"
CONF_SESSION_TOKEN = "session_token"
CONF_OTP_CODE = "otp_code"
CONF_OTP_SECRET = "otp_secret"
CONF_SESSION_EXPIRES_DAYS = "session_expires_days"
CONF_USE_SSL = "use_ssl"
CONF_VERIFY_SSL = "verify_ssl"
CONF_SCAN_INTERVAL = "scan_interval"

DEFAULT_PORT = 8088
DEFAULT_USERNAME = "peter"
DEFAULT_SCAN_INTERVAL = 300  # seconds
DEFAULT_SESSION_EXPIRES_DAYS = 1825

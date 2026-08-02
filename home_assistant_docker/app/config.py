from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    bridge_username: str = "healthpit"
    bridge_api_token: str
    bridge_otp_shared_secret: str = ""
    hevy_api_key: str = ""
    hevy_sync_enabled: bool = False
    hevy_max_pages: int = 10
    hevy_sync_interval_minutes: int = 60
    garmin_email: str = ""
    garmin_password: str = ""
    garmin_sync_enabled: bool = False
    garmin_activity_limit: int = 200
    database_path: str = "/data/db/healthpit_bridge.sqlite3"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()

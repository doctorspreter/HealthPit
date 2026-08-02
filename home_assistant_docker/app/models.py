from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import AliasChoices, BaseModel, ConfigDict, Field, field_validator, model_validator


Category = Literal[
    "activity",
    "workouts",
    "heart",
    "sleep",
    "body",
    "nutrition",
    "vitals",
]
WorkoutSource = Literal["manual", "apple_health", "gpx", "tcx", "garmin", "gympit"]


def normalize_workout_source(value: object) -> object:
    if value is None:
        return "manual"
    if not isinstance(value, str):
        return value
    key = value.strip().lower().replace("-", "_").replace(" ", "_")
    if not key:
        return "manual"
    aliases = {
        "apple": "apple_health",
        "applehealth": "apple_health",
        "apple_healthkit": "apple_health",
        "healthkit": "apple_health",
        "health": "apple_health",
        "gym_pit": "gympit",
        "gympit_iphone": "gympit",
        "gympit_(iphone)": "gympit",
        "healthpit_iphone": "apple_health",
        "healthpit_(iphone)": "apple_health",
    }
    return aliases.get(key, key)


class HealthMetricIn(BaseModel):
    id: str = Field(min_length=1, max_length=120)
    category: Category
    title: str = Field(min_length=1, max_length=120)
    value: float
    unit: str = Field(default="", max_length=40)
    measured_at: datetime
    aggregation: Literal["sum", "average", "latest"] = "latest"
    icon: str | None = None
    device_class: str | None = None
    state_class: Literal["measurement", "total", "total_increasing"] | None = None


class HealthBatchIn(BaseModel):
    device_id: str = Field(min_length=1, max_length=80)
    metrics: list[HealthMetricIn] = Field(min_length=1, max_length=500)


class AppSessionCreateIn(BaseModel):
    username: str = Field(min_length=1, max_length=80)
    api_token: str = Field(min_length=1, max_length=500)
    otp_code: str = Field(default="", max_length=20)
    device_name: str = Field(default="App", min_length=1, max_length=120)
    scope: Literal["workout_import", "home_assistant"] = "workout_import"
    client_app: Literal["healthpit", "gympit", "home_assistant"] = "home_assistant"
    node_role: Literal["master", "slave"]
    expires_days: int | None = Field(default=None, ge=1, le=3650)


class WorkoutRoutePointIn(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")

    latitude: float
    longitude: float
    elevation: float | None = None
    timestamp: datetime | None = None
    heart_rate: float | None = Field(default=None, validation_alias=AliasChoices("heart_rate", "heartRate"))


class WorkoutWeatherIn(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")

    condition: str | None = Field(default=None, max_length=120)
    temperatureCelsius: float | None = Field(default=None, validation_alias=AliasChoices("temperatureCelsius", "temperature_celsius"))
    humidityPercent: float | None = Field(default=None, validation_alias=AliasChoices("humidityPercent", "humidity_percent"))


class WorkoutInjuryIn(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")

    location: str = Field(default="", max_length=120)
    painType: str = Field(default="", max_length=120)
    severity: int = Field(default=0, ge=0, le=10)


class ImportedWorkoutSetIn(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")

    id: str = Field(default="", max_length=120)
    index: int = Field(default=0, ge=0)
    type: str = Field(default="Arbeit", max_length=80)
    reps: float | None = None
    weight_kg: float | None = Field(default=None, validation_alias=AliasChoices("weight_kg", "weightKg"))
    rpe: float | None = None
    volume_kg: float | None = Field(default=None, validation_alias=AliasChoices("volume_kg", "volumeKg"))
    is_personal_record: bool = Field(default=False, validation_alias=AliasChoices("is_personal_record", "isPersonalRecord"))

    @field_validator("id", "type", mode="before")
    @classmethod
    def empty_string_for_none(cls, value: object) -> str:
        return "" if value is None else str(value)

    @field_validator("index", mode="before")
    @classmethod
    def index_or_zero(cls, value: object) -> int:
        return 0 if value in (None, "") else int(value)

    @field_validator("reps", "weight_kg", "rpe", "volume_kg", mode="before")
    @classmethod
    def optional_number(cls, value: object) -> object:
        return None if value in (None, "") else value


class ImportedWorkoutExerciseIn(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")

    id: str = Field(default="", max_length=120)
    catalog_id: str = Field(default="", max_length=160, validation_alias=AliasChoices("catalog_id", "catalogId"))
    name: str = Field(default="Übung", max_length=180)
    category: str = Field(default="", max_length=120)
    start: datetime | None = Field(default=None, validation_alias=AliasChoices("start", "start_time", "startTime", "startDate"))
    end: datetime | None = Field(default=None, validation_alias=AliasChoices("end", "end_time", "endTime", "endDate"))
    duration_seconds: float | None = Field(default=None, validation_alias=AliasChoices("duration_seconds", "durationSeconds"))
    notes: str = Field(default="", max_length=2000)
    device_settings: dict[str, Any] = Field(default_factory=dict, validation_alias=AliasChoices("device_settings", "deviceSettings"))
    sets: list[ImportedWorkoutSetIn] = Field(default_factory=list, max_length=1000)

    @field_validator("id", "catalog_id", "category", "notes", mode="before")
    @classmethod
    def empty_string_for_none(cls, value: object) -> str:
        return "" if value is None else str(value)

    @field_validator("name", mode="before")
    @classmethod
    def exercise_name_or_default(cls, value: object) -> str:
        text = "" if value is None else str(value).strip()
        return text or "Übung"

    @field_validator("device_settings", mode="before")
    @classmethod
    def settings_or_empty(cls, value: object) -> dict[str, Any]:
        return value if isinstance(value, dict) else {}

    @field_validator("duration_seconds", mode="before")
    @classmethod
    def optional_number(cls, value: object) -> object:
        return None if value in (None, "") else value

    @field_validator("sets", mode="before")
    @classmethod
    def sets_or_empty(cls, value: object) -> list[object]:
        return value if isinstance(value, list) else []


class ImportedWorkoutIn(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")

    id: str = Field(min_length=1, max_length=120, validation_alias=AliasChoices("id", "workout_id", "workoutId", "uuid"))
    source: WorkoutSource = "manual"
    sport: str = Field(default="Workout", min_length=1, max_length=80)
    title: str = Field(default="Workout", min_length=1, max_length=160)
    start: datetime = Field(validation_alias=AliasChoices("start", "start_time", "startTime", "startDate"))
    end: datetime = Field(validation_alias=AliasChoices("end", "end_time", "endTime", "endDate"))
    duration_minutes: float | None = Field(default=None, validation_alias=AliasChoices("duration_minutes", "durationMinutes"))
    distance_km: float | None = Field(default=None, validation_alias=AliasChoices("distance_km", "distanceKm"))
    energy_kcal: float | None = Field(default=None, validation_alias=AliasChoices("energy_kcal", "energyKcal", "calories", "kcal"))
    average_heart_rate: float | None = Field(default=None, validation_alias=AliasChoices("average_heart_rate", "averageHeartRate", "avgHeartRate"))
    max_heart_rate: float | None = Field(default=None, validation_alias=AliasChoices("max_heart_rate", "maxHeartRate"))
    notes: str = Field(default="", max_length=2000)
    weather: WorkoutWeatherIn | None = None
    injury: WorkoutInjuryIn | None = None
    exercises: list[ImportedWorkoutExerciseIn] = Field(default_factory=list, max_length=500)
    route: list[WorkoutRoutePointIn] = Field(default_factory=list, max_length=20000)

    @model_validator(mode="before")
    @classmethod
    def fill_missing_end(cls, values: object) -> object:
        if isinstance(values, dict) and not any(values.get(key) for key in ("end", "end_time", "endTime", "endDate")):
            for key in ("start", "start_time", "startTime", "startDate"):
                if values.get(key):
                    values = {**values, "end": values[key]}
                    break
        return values

    @field_validator("id", mode="before")
    @classmethod
    def id_to_string(cls, value: object) -> object:
        return value if isinstance(value, str) else str(value or "")

    @field_validator("sport", "title", mode="before")
    @classmethod
    def required_text_or_default(cls, value: object) -> str:
        text = "" if value is None else str(value).strip()
        return text or "Workout"

    @field_validator("notes", mode="before")
    @classmethod
    def notes_or_empty(cls, value: object) -> str:
        return "" if value is None else str(value)

    @field_validator("duration_minutes", "distance_km", "energy_kcal", "average_heart_rate", "max_heart_rate", mode="before")
    @classmethod
    def optional_number(cls, value: object) -> object:
        return None if value in (None, "") else value

    @field_validator("exercises", "route", mode="before")
    @classmethod
    def list_or_empty(cls, value: object) -> list[object]:
        return value if isinstance(value, list) else []

    @field_validator("source", mode="before")
    @classmethod
    def normalize_source(cls, value: object) -> object:
        return normalize_workout_source(value)


class ImportedWorkoutBatchIn(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")

    device_id: str = Field(min_length=1, max_length=120, validation_alias=AliasChoices("device_id", "deviceId"))
    workouts: list[ImportedWorkoutIn] = Field(default_factory=list, max_length=1000)

    @field_validator("device_id", mode="before")
    @classmethod
    def device_id_to_string(cls, value: object) -> object:
        return value if isinstance(value, str) else str(value or "")

    @field_validator("workouts", mode="before")
    @classmethod
    def workouts_or_empty(cls, value: object) -> list[object]:
        return value if isinstance(value, list) else []


class WorkoutLinkOverrideIn(BaseModel):
    primary: str = Field(min_length=1, max_length=260)
    linked: str = Field(min_length=1, max_length=260)
    action: Literal["merge", "separate"]


class WorkoutReconcileIn(BaseModel):
    device_id: str = Field(min_length=1, max_length=80)
    source: WorkoutSource
    workout_ids: list[str] = Field(default_factory=list, max_length=50000)

    @field_validator("source", mode="before")
    @classmethod
    def normalize_source(cls, value: object) -> object:
        return normalize_workout_source(value)

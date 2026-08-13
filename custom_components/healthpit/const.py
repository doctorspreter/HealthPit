"""Constants for the Healthpit integration."""

from __future__ import annotations

DOMAIN = "healthpit"

# The apps push here; Home Assistant's own authentication guards the routes.
API_BASE = f"/api/{DOMAIN}/v1"

# Everything the apps sent lives in Home Assistant's own storage. The recorder
# purges states after ten days by default, so workout history needs its own
# place to survive that and a restart.
# Version 2 adds the canonical metric id and the provider fields to every
# stored value. The upgrade runs once, keeps every storage key as it was and
# therefore leaves entity ids and their history untouched.
STORAGE_VERSION = 2
STORAGE_KEY = DOMAIN

# Guard rails so a looping client cannot grow the store without bound.
# Per Home Assistant user, not in total.
MAX_WORKOUTS_PER_USER = 5000
MAX_METRICS_PER_USER = 5000

# Batched writes: pushes arrive in bursts while a workout syncs.
SAVE_DELAY_SECONDS = 10

SERVICE_DELETE_WORKOUT = "delete_workout"
SERVICE_SAVE_WORKOUT_LINK = "save_workout_link"
SERVICE_DELETE_WORKOUT_LINK = "delete_workout_link"
SERVICE_IMPORT_HISTORY = "import_history"
SERVICE_FORGET_USER = "forget_user"

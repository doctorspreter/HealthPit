"""GymPit workouts create Home Assistant entity descriptors dynamically."""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path


_PATH = (
    Path(__file__).parents[1]
    / "custom_components"
    / "healthpit"
    / "workout_entities.py"
)
_SPEC = spec_from_file_location("healthpit_workout_entities", _PATH)
assert _SPEC and _SPEC.loader
workout_entities = module_from_spec(_SPEC)
_SPEC.loader.exec_module(workout_entities)


def test_gympit_workout_discovers_sport_and_exercise_entities() -> None:
    metrics = workout_entities.build_workout_metrics(
        [
            {
                "workout_id": "gympit-session-1",
                "source": "gympit",
                "sport": "strength_training",
                "title": "Push",
                "start_time": "2026-08-08T08:00:00+00:00",
                "end_time": "2026-08-08T09:00:00+00:00",
                "duration_seconds": 3600,
                "exercises": [
                    {
                        "catalog_id": "bench_press",
                        "name": "Bankdrücken",
                        "category": "chest",
                        "sets": [
                            {"reps": 8, "weight_kg": 80, "volume_kg": 640},
                            {"reps": 6, "weight_kg": 85, "volume_kg": 510},
                        ],
                    }
                ],
            }
        ]
    )

    by_key = {item["key"]: item for item in metrics}
    assert by_key["sport:krafttraining:count"]["value"] == 1
    assert by_key["exercise:bench_press:weight"]["value"] == 85
    assert by_key["exercise:bench_press:total_volume"]["value"] == 1150
    assert by_key["exercise:bench_press:weight"]["attributes"]["source"] == "gympit"

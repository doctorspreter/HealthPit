"""GymPit workouts create Home Assistant entity descriptors dynamically.

Two rules hold this together. A sport descriptor has to say which sport and
which sources it came from, because the sensor picks its device from that —
strength training out of GymPit belongs with the machines, a run belongs with
running. And an exercise descriptor must be limited to what a single value
cannot say: the last weight and the last repetitions arrive as their own values
from GymPit, and repeating them here is what put every machine into two places
at once.
"""

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


def _session(**overrides):
    workout = {
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
    workout.update(overrides)
    return workout


def _by_key(workouts):
    return {item["key"]: item for item in workout_entities.build_workout_metrics(workouts)}


def test_a_gympit_session_produces_sport_and_exercise_descriptors() -> None:
    by_key = _by_key([_session()])

    assert by_key["sport:krafttraining:count"]["value"] == 1
    assert by_key["exercise:bench_press:total_volume"]["value"] == 1150
    assert by_key["exercise:bench_press:sessions"]["value"] == 1
    assert by_key["exercise:bench_press:best_weight"]["value"] == 85


def test_a_sport_descriptor_says_where_it_belongs() -> None:
    """The sensor reads sport and sources to find its device. Without them it
    would have to take the key apart, and every change to the key format would
    silently move the sensors somewhere else."""
    descriptor = _by_key([_session()])["sport:krafttraining:count"]

    assert descriptor["sport_key"] == "krafttraining"
    assert descriptor["sources"] == ["gympit"]


def test_an_exercise_descriptor_names_its_exercise() -> None:
    descriptor = _by_key([_session()])["exercise:bench_press:sessions"]

    assert descriptor["exercise_key"] == "bench_press"
    assert descriptor["exercise"] == "Bankdrücken"
    assert descriptor["attributes"]["source"] == "gympit"


def test_the_last_set_is_not_repeated_as_an_exercise_descriptor() -> None:
    """Weight, repetitions, volume and RPE of the last set are their own
    sensors, fed by the canonical values. Here they would be a second copy."""
    keys = _by_key([_session()])

    for repeated in ("weight", "reps", "volume", "rpe", "sets"):
        assert f"exercise:bench_press:{repeated}" not in keys


def test_the_names_no_longer_carry_the_sport_or_the_language() -> None:
    """The device is called "Peter Run"; repeating it in the sensor name gave
    entity IDs like sensor.peter_run_laufen_distanz."""
    by_key = _by_key([_session()])

    assert by_key["sport:krafttraining:count"]["name"] == "Sessions"
    assert by_key["sport:krafttraining:total_duration"]["name"] == "Total time"


def test_several_sessions_add_up() -> None:
    by_key = _by_key(
        [
            _session(),
            _session(
                workout_id="gympit-session-2",
                start_time="2026-08-11T08:00:00+00:00",
                end_time="2026-08-11T09:00:00+00:00",
            ),
        ]
    )

    assert by_key["exercise:bench_press:sessions"]["value"] == 2
    assert by_key["exercise:bench_press:total_volume"]["value"] == 2300
    assert by_key["sport:krafttraining:count"]["value"] == 2


def test_the_canonical_sport_type_wins_over_the_display_name() -> None:
    """The app has the sport language-neutrally in its database. Once it sends
    it, nothing here has to be guessed from a translated name."""
    assert (
        workout_entities.sport_name({"sport_type": "RUNNING", "sport": "Running"})
        == "Laufen"
    )
    assert (
        workout_entities.sport_name(
            {"sport_type": "STRENGTH_TRAINING", "sport": "Krafttraining"}
        )
        == "Krafttraining"
    )
    # Auch eine Sportart ohne eigenen Namen bleibt eindeutig.
    assert (
        workout_entities.sport_name({"sport_type": "PADDLE_SPORTS", "sport": "Paddeln"})
        == "Paddle Sports"
    )


def test_without_the_canonical_type_the_display_name_still_works() -> None:
    """Everything already stored, and every older app, has no sport_type."""
    assert workout_entities.sport_name({"sport": "Outdoor Run"}) == "Laufen"


def test_one_sport_stays_one_sport_however_it_is_written() -> None:
    """The sport arrives as a translated display name — "Laufen" in German,
    "Running" in English, "Outdoor Run" from another source. Compared letter
    for letter, one sport fell apart into several, and the device for it
    counted only the sessions that happened to be spelled its way."""
    for written in (
        "Laufen",
        "running",
        "Outdoor Run",
        "Laufen im Freien",
        "Trailrunning",
        "Laufband",
        "Jogging",
    ):
        assert workout_entities.sport_name({"sport": written}) == "Laufen", written

    for written in ("Gehen", "walking", "Nordic Walking"):
        assert workout_entities.sport_name({"sport": written}) == "Gehen", written

    for written in ("Radfahren", "Cycling", "Indoor Bike", "Spinning"):
        assert workout_entities.sport_name({"sport": written}) == "Radfahren", written


def test_a_word_is_only_matched_at_its_start() -> None:
    """"t-rad-itional strength training" is not cycling. Matching anywhere in
    the string put it under Radfahren."""
    assert (
        workout_entities.sport_name({"sport": "traditional_strength_training"})
        == "Krafttraining"
    )
    assert workout_entities.sport_name({"sport": "Bergsteigen"}) == "Bergsteigen"
    assert workout_entities.sport_name({"sport": "Rugby"}) == "Rugby"


def test_an_unknown_sport_keeps_its_own_name() -> None:
    """Folding everything unknown into one bucket would be worse than a device
    of its own."""
    assert workout_entities.sport_name({"sport": "Tennis"}) == "Tennis"
    assert workout_entities.sport_name({"sport": "Crosstrainer"}) == "Crosstrainer"
    assert workout_entities.sport_name({"sport": ""}) == "Workout"


def test_sessions_of_the_same_sport_written_differently_count_as_one() -> None:
    by_key = _by_key(
        [
            _session(workout_id="1", sport="Laufen", source="apple_health",
                     distance_km=6.0, exercises=[]),
            _session(workout_id="2", sport="Outdoor Run", source="apple_health",
                     start_time="2026-08-09T08:00:00+00:00", distance_km=5.0, exercises=[]),
        ]
    )

    assert by_key["sport:laufen:count"]["value"] == 2
    assert by_key["sport:laufen:total_distance"]["value"] == 11.0


def test_the_exercise_volume_helper_falls_back_to_weight_times_reps() -> None:
    """GymPit sends volume_kg; other sources may not."""
    volume = workout_entities.exercise_volume(
        {"sets": [{"reps": 10, "weight_kg": 40}, {"reps": 8, "weight_kg": 45}]}
    )
    assert volume == 760


def test_a_gympit_session_arrives_with_its_canonical_sport() -> None:
    """GymPit sends the identifier now, not just the name. Without it the
    integration had to read "strength_training" and hope."""
    by_key = _by_key([_session(sport="strength_training", sport_type="STRENGTH_TRAINING")])
    assert "sport:krafttraining:count" in by_key
    assert by_key["sport:krafttraining:count"]["sources"] == ["gympit"]


def test_an_unknown_canonical_sport_still_gets_a_readable_name() -> None:
    assert workout_entities.sport_name({"sport_type": "PADDLE_SPORTS"}) == "Paddle Sports"
    assert workout_entities.sport_name({"sport_type": "  running  "}) == "Laufen"

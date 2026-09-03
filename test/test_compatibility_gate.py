"""Übergangscode – HEALTHPIT-COMPAT-2026-08.

The integration has to handle both app versions: the old one that sends only
sensor ids, and the new one that sends metric ids. Nothing is rejected —
the old format is translated on the way in and the user gets a repair notice.

Delete this file together with the rest of the compatibility layer; see
PROMPT-KOMPATIBILITAET-ENTFERNEN.md.
"""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import sys
import types


_COMPONENT = Path(__file__).parents[1] / "custom_components" / "healthpit"


def _load(name: str):
    package = "healthpit_component"
    if package not in sys.modules:
        shim = types.ModuleType(package)
        shim.__path__ = [str(_COMPONENT)]
        sys.modules[package] = shim
    full_name = f"{package}.{name}"
    if full_name in sys.modules:
        return sys.modules[full_name]
    spec = spec_from_file_location(full_name, _COMPONENT / f"{name}.py")
    assert spec and spec.loader
    module = module_from_spec(spec)
    sys.modules[full_name] = module
    spec.loader.exec_module(module)
    return module


compatibility = _load("compatibility")


def test_a_current_app_is_recognised() -> None:
    body = {"device_id": "iphone", "model_version": 2, "metrics": []}
    assert compatibility.app_is_current(body)


def test_an_app_without_the_field_counts_as_the_old_one() -> None:
    # No field at all means a build from before the rebuild.
    assert compatibility.app_model_version({"device_id": "iphone"}) == 1
    assert not compatibility.app_is_current({"device_id": "iphone"})


def test_the_header_works_as_well() -> None:
    assert compatibility.app_model_version({}, {"X-HealthPit-Model-Version": "2"}) == 2


def test_garbage_is_treated_as_old_rather_than_crashing() -> None:
    assert compatibility.app_model_version({"model_version": "übermorgen"}) == 1
    assert compatibility.app_model_version({"model_version": None}) == 1
    assert compatibility.app_model_version("not a dict") == 1


def test_values_from_an_old_app_are_marked_not_dropped() -> None:
    metrics = [{"metric_id": "step_count", "canonical_metric_id": "ACT_STEPS"}]
    annotated = compatibility.annotate(metrics, 1)

    assert annotated[0]["app_model_version"] == 1
    # The canonical id was derived by the integration, not sent by the app.
    assert annotated[0]["metric_id_source"] == "derived"
    assert annotated[0]["canonical_metric_id"] == "ACT_STEPS"


def test_values_from_a_current_app_say_so() -> None:
    annotated = compatibility.annotate([{"metric_id": "step_count"}], 2)
    assert annotated[0]["metric_id_source"] == "app"


def test_the_notice_is_per_device() -> None:
    assert compatibility.issue_id("iphone") != compatibility.issue_id("ipad")
    assert compatibility.issue_id("") == "outdated_app_unknown"


def test_status_tells_the_app_which_side_it_is_talking_to() -> None:
    fields = compatibility.status_fields()
    assert fields["model_version"] == compatibility.MODEL_VERSION
    assert fields["recommended_app_model_version"] == compatibility.RECOMMENDED_APP_MODEL_VERSION
    assert fields["accepts_legacy_app"] is True
    # An app built against the first draft read this name and refused to sync
    # when it was missing.
    assert fields["required_app_model_version"] == compatibility.RECOMMENDED_APP_MODEL_VERSION



# ---------------------------------------------------------------------------
# Both app versions end up with the same stored value
# ---------------------------------------------------------------------------


payload = _load("payload")


def _push(**extra):
    """A metric as one of the two app versions would send it."""
    base = {
        "id": "step_count",
        "category": "activity",
        "title": "Schritte",
        "value": 8431,
        "unit": "Schritte",
        "measured_at": "2026-08-12T10:00:00+00:00",
        "aggregation": "sum",
    }
    base.update(extra)
    return base


def test_old_and_new_app_produce_the_same_metric_id() -> None:
    old = payload.normalize_metric(_push())
    new = payload.normalize_metric(_push(metric_id="ACT_STEPS", origin_provider="APP"))

    assert old["canonical_metric_id"] == new["canonical_metric_id"] == "ACT_STEPS"
    # And the storage key — the entity id — is identical either way.
    assert old["metric_id"] == new["metric_id"] == "step_count"
    assert old["value"] == new["value"] == 8431


def test_the_old_app_keeps_its_extra_fields_empty_rather_than_wrong() -> None:
    old = payload.normalize_metric(_push())

    # Nothing invented: the app said nothing about where the value came from,
    # so the default stands and the observation id stays empty.
    assert old["origin_provider"] == "APP"
    assert old["observation_id"] is None
    assert old["unit_code"] is None


def test_a_new_app_can_say_the_value_came_from_garmin() -> None:
    new = payload.normalize_metric(
        _push(metric_id="ACT_STEPS", origin_provider="GAR", ingest_provider="APP")
    )
    assert new["origin_provider"] == "GAR"
    assert new["ingest_provider"] == "APP"

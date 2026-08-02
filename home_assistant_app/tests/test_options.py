"""Tests for the grouped configuration options."""

from __future__ import annotations

from unittest import TestCase

from app import bootstrap


class GroupedOptionTests(TestCase):
    def test_groups_are_flattened_to_internal_names(self) -> None:
        flat = bootstrap.flatten_options(
            {
                "garmin": {"enabled": True, "email": "a@b.c", "activity_limit": 50},
                "hevy": {"api_key": "key", "interval_minutes": 30},
                "access": {"username": "peter", "session_days": 10},
                "system": {"log_level": "debug"},
            }
        )
        self.assertEqual(flat["garmin_sync_enabled"], True)
        self.assertEqual(flat["garmin_email"], "a@b.c")
        self.assertEqual(flat["garmin_activity_limit"], 50)
        self.assertEqual(flat["hevy_api_key"], "key")
        self.assertEqual(flat["hevy_sync_interval_minutes"], 30)
        self.assertEqual(flat["bridge_username"], "peter")
        self.assertEqual(flat["app_session_expires_days"], 10)
        self.assertEqual(flat["log_level"], "debug")

    def test_legacy_flat_options_still_apply(self) -> None:
        flat = bootstrap.flatten_options({"garmin_email": "old@example.com"})
        self.assertEqual(flat["garmin_email"], "old@example.com")

    def test_groups_win_over_legacy_keys(self) -> None:
        flat = bootstrap.flatten_options(
            {"garmin_email": "old@example.com", "garmin": {"email": "new@example.com"}}
        )
        self.assertEqual(flat["garmin_email"], "new@example.com")

    def test_partial_groups_leave_other_fields_untouched(self) -> None:
        flat = bootstrap.flatten_options({"garmin": {"email": "a@b.c"}})
        self.assertNotIn("garmin_password", flat)
        self.assertNotIn("garmin", flat)

    def test_non_dict_group_is_ignored(self) -> None:
        self.assertEqual(bootstrap.flatten_options({"garmin": "nonsense"}), {})

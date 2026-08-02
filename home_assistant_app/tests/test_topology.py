"""Tests for master/slave option resolution."""

from __future__ import annotations

import json
from pathlib import Path
import tempfile
from unittest import TestCase
from unittest.mock import patch

from app import bootstrap


VALID_TOKEN = "t" * 40


class MasterUrlTests(TestCase):
    def test_bare_host_gets_scheme_and_default_port(self) -> None:
        self.assertEqual(
            bootstrap.normalize_master_url("192.168.178.20"),
            "http://192.168.178.20:8088",
        )

    def test_host_with_port_keeps_the_port(self) -> None:
        self.assertEqual(
            bootstrap.normalize_master_url("healthpit-bridge:9000"),
            "http://healthpit-bridge:9000",
        )

    def test_full_url_is_preserved_and_trimmed(self) -> None:
        self.assertEqual(
            bootstrap.normalize_master_url("https://bridge.example.com:8443/ "),
            "https://bridge.example.com:8443",
        )

    def test_empty_stays_empty(self) -> None:
        self.assertEqual(bootstrap.normalize_master_url("  "), "")


class GroupedOptionTests(TestCase):
    def test_groups_are_flattened_to_internal_names(self) -> None:
        flat = bootstrap.flatten_options(
            {
                "garmin": {"enabled": True, "email": "a@b.c", "activity_limit": 50},
                "hevy": {"api_key": "key", "interval_minutes": 30},
                "access": {"username": "peter", "session_days": 10},
                "topology": {"role": "slave", "master_url": "10.0.0.5"},
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
        self.assertEqual(flat["node_role"], "slave")
        self.assertEqual(flat["master_url"], "10.0.0.5")
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


class NodeRoleTests(TestCase):
    def _resolve(self, options: dict[str, object]) -> tuple[dict, dict]:
        with tempfile.TemporaryDirectory() as directory:
            options_path = Path(directory) / "options.json"
            options_path.write_text(json.dumps(options), encoding="utf-8")
            with patch.object(bootstrap, "OPTIONS_PATH", options_path), patch.object(
                bootstrap, "GENERATED_SECRETS_PATH", Path(directory) / "generated.json"
            ):
                return bootstrap.resolve_options()

    def test_master_is_the_default(self) -> None:
        resolved, environment = self._resolve({})
        self.assertEqual(resolved["node_role"], "master")
        self.assertEqual(environment["NODE_ROLE"], "master")

    def test_unknown_role_falls_back_to_master(self) -> None:
        resolved, _ = self._resolve({"node_role": "primary"})
        self.assertEqual(resolved["node_role"], "master")

    def test_slave_requires_a_master_url(self) -> None:
        with self.assertRaises(ValueError) as error:
            self._resolve({"node_role": "slave", "master_api_token": VALID_TOKEN})
        self.assertIn("master_url", str(error.exception))

    def test_grouped_slave_options_are_resolved(self) -> None:
        resolved, environment = self._resolve(
            {
                "topology": {
                    "role": "slave",
                    "master_url": "10.0.0.5",
                    "master_api_token": VALID_TOKEN,
                },
                "access": {"username": "peter"},
            }
        )
        self.assertEqual(resolved["node_role"], "slave")
        self.assertEqual(environment["MASTER_URL"], "http://10.0.0.5:8088")
        self.assertEqual(environment["BRIDGE_USERNAME"], "peter")

    def test_slave_requires_a_master_token(self) -> None:
        with self.assertRaises(ValueError) as error:
            self._resolve({"node_role": "slave", "master_url": "10.0.0.5"})
        self.assertIn("master_api_token", str(error.exception))

    def test_slave_defaults_username_to_the_bridge_username(self) -> None:
        resolved, environment = self._resolve(
            {
                "node_role": "slave",
                "master_url": "10.0.0.5",
                "master_api_token": VALID_TOKEN,
                "bridge_username": "peter",
            }
        )
        self.assertEqual(resolved["master_username"], "peter")
        self.assertEqual(environment["MASTER_URL"], "http://10.0.0.5:8088")
        self.assertEqual(environment["MASTER_API_TOKEN"], VALID_TOKEN)

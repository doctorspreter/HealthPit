"""Tests for Home Assistant app bootstrap and Supervisor discovery."""

from __future__ import annotations

import os
from unittest import TestCase
from unittest.mock import patch

from app import bootstrap


class SupervisorDiscoveryTests(TestCase):
    def test_discovery_registers_without_credentials(self) -> None:
        calls: list[tuple[str, str, dict[str, object] | None]] = []

        def fake_request(
            method: str,
            path: str,
            _token: str,
            payload: dict[str, object] | None = None,
        ) -> dict[str, object]:
            calls.append((method, path, payload))
            if path == "/addons/self/info":
                return {"hostname": "abc123-healthpit-bridge", "slug": "abc123_healthpit_bridge"}
            if path == "/discovery":
                return {"discovery": []}
            return {}

        with patch.dict(os.environ, {"SUPERVISOR_TOKEN": "test-token"}), patch.object(
            bootstrap, "supervisor_request", side_effect=fake_request
        ):
            bootstrap.register_supervisor_discovery({"BRIDGE_USERNAME": "healthpit"})

        post = next(call for call in calls if call[:2] == ("POST", "/discovery"))
        self.assertEqual(
            post[2],
            {
                "service": "healthpit_bridge",
                "config": {
                    "host": "abc123-healthpit-bridge",
                    "port": 8088,
                    "username": "healthpit",
                    "use_ssl": False,
                    "verify_ssl": True,
                },
            },
        )
        self.assertNotIn("token", post[2]["config"])

    def test_discovery_is_optional_outside_supervisor(self) -> None:
        with patch.dict(os.environ, {}, clear=True), patch.object(
            bootstrap, "supervisor_request"
        ) as request:
            bootstrap.register_supervisor_discovery({"BRIDGE_USERNAME": "healthpit"})
        request.assert_not_called()

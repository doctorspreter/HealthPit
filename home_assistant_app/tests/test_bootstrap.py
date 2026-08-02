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
            bootstrap.register_supervisor_discovery(
                {"BRIDGE_USERNAME": "healthpit", "NODE_ROLE": "master"}
            )

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

    def test_discovery_carries_only_the_session_token(self) -> None:
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
            bootstrap.register_supervisor_discovery(
                {"BRIDGE_USERNAME": "healthpit", "NODE_ROLE": "master"},
                "hbs_session",
            )

        config = next(
            call for call in calls if call[:2] == ("POST", "/discovery")
        )[2]["config"]
        self.assertEqual(config["session_token"], "hbs_session")
        # The API token and the TOTP secret must never be advertised.
        self.assertNotIn("token", config)
        self.assertNotIn("api_token", config)
        self.assertNotIn("otp_secret", config)

    def test_registration_never_reads_or_deletes_discovery(self) -> None:
        """GET and DELETE on /discovery are Home Assistant only and answer 401."""
        calls: list[tuple[str, str]] = []

        def fake_request(
            method: str,
            path: str,
            _token: str,
            payload: dict[str, object] | None = None,
        ) -> dict[str, object]:
            calls.append((method, path))
            if path == "/discovery" and method != "POST":
                raise AssertionError(f"{method} /discovery is forbidden for an app")
            if path.startswith("/discovery/"):
                raise AssertionError(f"{method} {path} is forbidden for an app")
            if path == "/addons/self/info":
                return {"hostname": "abc123-healthpit-bridge", "slug": "abc123_healthpit_bridge"}
            return {}

        with patch.dict(os.environ, {"SUPERVISOR_TOKEN": "test-token"}), patch.object(
            bootstrap, "supervisor_request", side_effect=fake_request
        ):
            bootstrap.register_supervisor_discovery(
                {"BRIDGE_USERNAME": "healthpit", "NODE_ROLE": "master"},
                "hbs_session",
            )

        self.assertIn(("POST", "/discovery"), calls)
        self.assertEqual(
            [call for call in calls if call[1].startswith("/discovery")],
            [("POST", "/discovery")],
        )

    def test_a_slave_does_not_advertise_itself(self) -> None:
        with patch.dict(os.environ, {"SUPERVISOR_TOKEN": "test-token"}), patch.object(
            bootstrap, "supervisor_request"
        ) as request:
            bootstrap.register_supervisor_discovery(
                {"BRIDGE_USERNAME": "healthpit", "NODE_ROLE": "slave"}
            )
        request.assert_not_called()

    def test_discovery_is_optional_outside_supervisor(self) -> None:
        with patch.dict(os.environ, {}, clear=True), patch.object(
            bootstrap, "supervisor_request"
        ) as request:
            bootstrap.register_supervisor_discovery(
                {"BRIDGE_USERNAME": "healthpit", "NODE_ROLE": "master"}
            )
        request.assert_not_called()

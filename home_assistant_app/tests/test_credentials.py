"""Tests for generated credentials becoming visible in the app options."""

from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile
from unittest import TestCase
from unittest.mock import patch

from app import bootstrap


class PublishGeneratedCredentialsTests(TestCase):
    def _publish(self, stored: dict, resolved: dict) -> dict | None:
        calls: list[dict] = []

        def fake_request(method, path, _token, payload=None):
            calls.append({"method": method, "path": path, "payload": payload})
            return {}

        with tempfile.TemporaryDirectory() as directory:
            options_path = Path(directory) / "options.json"
            options_path.write_text(json.dumps(stored), encoding="utf-8")
            with patch.dict(os.environ, {"SUPERVISOR_TOKEN": "t"}), patch.object(
                bootstrap, "OPTIONS_PATH", options_path
            ), patch.object(bootstrap, "supervisor_request", side_effect=fake_request):
                bootstrap.publish_generated_credentials(resolved)
        return calls[0] if calls else None

    def test_a_generated_token_is_written_into_the_options(self) -> None:
        call = self._publish(
            {"access": {"api_token": "", "regenerate_api_token": True}},
            {
                "credential_mode": "automatic",
                "bridge_api_token": "generated-token",
                "otp_mode": "disabled",
                "bridge_otp_shared_secret": "",
            },
        )
        self.assertIsNotNone(call)
        self.assertEqual(call["method"], "POST")
        self.assertEqual(call["path"], "/addons/self/options")
        access = call["payload"]["options"]["access"]
        self.assertEqual(access["api_token"], "generated-token")
        # The one-shot switch has to turn itself back off.
        self.assertIs(access["regenerate_api_token"], False)

    def test_a_generated_totp_secret_is_written_too(self) -> None:
        call = self._publish(
            {"access": {}},
            {
                "credential_mode": "automatic",
                "bridge_api_token": "generated-token",
                "otp_mode": "automatic",
                "bridge_otp_shared_secret": "JBSWY3DPEHPK3PXP",
            },
        )
        self.assertEqual(
            call["payload"]["options"]["access"]["totp_secret"], "JBSWY3DPEHPK3PXP"
        )

    def test_a_manual_token_is_never_overwritten(self) -> None:
        call = self._publish(
            {"access": {"api_token": "my-own-token", "regenerate_api_token": False}},
            {
                "credential_mode": "manual",
                "bridge_api_token": "my-own-token",
                "otp_mode": "manual",
                "bridge_otp_shared_secret": "JBSWY3DPEHPK3PXP",
            },
        )
        self.assertIsNone(call, "nothing changed, so nothing may be written")

    def test_other_groups_survive_the_write(self) -> None:
        call = self._publish(
            {
                "access": {"api_token": ""},
                "garmin": {"enabled": True, "email": "a@b.c"},
                "system": {"log_level": "debug"},
            },
            {
                "credential_mode": "automatic",
                "bridge_api_token": "generated-token",
                "otp_mode": "disabled",
                "bridge_otp_shared_secret": "",
            },
        )
        options = call["payload"]["options"]
        self.assertEqual(options["garmin"], {"enabled": True, "email": "a@b.c"})
        self.assertEqual(options["system"], {"log_level": "debug"})

    def test_nothing_is_written_without_a_supervisor(self) -> None:
        with patch.dict(os.environ, {}, clear=True), patch.object(
            bootstrap, "supervisor_request"
        ) as request:
            bootstrap.publish_generated_credentials(
                {
                    "credential_mode": "automatic",
                    "bridge_api_token": "generated-token",
                    "otp_mode": "disabled",
                    "bridge_otp_shared_secret": "",
                }
            )
        request.assert_not_called()


class RegenerationTests(TestCase):
    def _resolve(self, options: dict) -> dict:
        with tempfile.TemporaryDirectory() as directory:
            options_path = Path(directory) / "options.json"
            options_path.write_text(json.dumps(options), encoding="utf-8")
            with patch.object(bootstrap, "OPTIONS_PATH", options_path), patch.object(
                bootstrap, "GENERATED_SECRETS_PATH", Path(directory) / "generated.json"
            ):
                resolved, _ = bootstrap.resolve_options()
        return resolved

    def test_an_automatic_token_is_random_and_16_characters(self) -> None:
        first = self._resolve({})["bridge_api_token"]
        second = self._resolve({})["bridge_api_token"]
        self.assertEqual(len(first), bootstrap.GENERATED_API_TOKEN_LENGTH)
        self.assertNotEqual(first, second)

    def test_a_short_manual_token_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            self._resolve({"access": {"token_mode": "manual", "api_token": "short"}})

    def test_an_eight_character_manual_token_is_accepted(self) -> None:
        resolved = self._resolve(
            {"access": {"token_mode": "manual", "api_token": "12345678"}}
        )
        self.assertEqual(resolved["bridge_api_token"], "12345678")

    def test_a_stored_token_is_kept_across_starts(self) -> None:
        kept = "k" * 50
        resolved = self._resolve({"access": {"api_token": kept}})
        self.assertEqual(resolved["bridge_api_token"], kept)

    def test_the_switch_forces_a_fresh_token(self) -> None:
        kept = "k" * 50
        resolved = self._resolve(
            {"access": {"api_token": kept, "regenerate_api_token": True}}
        )
        self.assertNotEqual(resolved["bridge_api_token"], kept)
        self.assertEqual(
            len(resolved["bridge_api_token"]), bootstrap.GENERATED_API_TOKEN_LENGTH
        )
        self.assertIs(resolved["regenerate_api_token"], False)

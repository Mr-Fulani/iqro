from __future__ import annotations

import argparse
import unittest
import uuid
from typing import Any

from ops.load.capacity import StageSpec
from ops.load.registered_capacity import (
    MAIL_DELIVERY_STEP,
    MailCodeResponse,
    MailpitHttpClient,
    RegisteredStageConfig,
    RegisteredStageSummary,
    bounded_stage,
    run_registered_user_journey,
    stage_payload,
    threshold_failures,
    validate_mailpit_url,
    validate_registered_authorization,
    validate_test_email_domain,
)
from ops.load.sync_capacity import JourneyResponse, JourneyResult


class FakeRegisteredJourneyClient:
    def __init__(self) -> None:
        self.revision = 0
        self.cursor = 0
        self.email = ""
        self.steps: list[str] = []
        self.closed = False

    def request(
        self,
        *,
        step: str,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        access_token: str | None = None,
        expected_statuses: tuple[int, ...] = (200,),
    ) -> JourneyResponse:
        del method, path, access_token, expected_statuses
        self.steps.append(step)
        status = 204 if step == "logout" else 200
        response_payload: dict[str, Any] | None = {}
        if step in {"guest-bootstrap", "token-refresh"}:
            response_payload = {
                "access_token": f"access-{len(self.steps)}",
                "refresh_token": f"refresh-{len(self.steps)}",
            }
        elif step == "email-start":
            assert payload is not None
            self.email = str(payload["email"])
            status = 202
            response_payload = {"challenge_id": str(uuid.uuid4())}
        elif step == "email-verify":
            response_payload = {
                "access_token": "registered-access",
                "refresh_token": "registered-refresh",
                "user": {"status": "active", "email": self.email},
            }
        elif step == "registered-session":
            response_payload = {"user": {"status": "active", "email": self.email}}
        elif step == "sync-push":
            assert payload is not None
            operations = payload["operations"]
            assert isinstance(operations, list)
            rows = []
            for operation in operations:
                self.revision += 1
                self.cursor += 1
                rows.append(
                    {
                        "operation_id": operation["operation_id"],
                        "outcome": "accepted",
                        "entity": {"revision": self.revision},
                    }
                )
            response_payload = {"results": rows, "cursor": self.cursor}
        elif step == "sync-pull":
            response_payload = {
                "mode": "incremental",
                "changes": [],
                "next_cursor": self.cursor,
                "has_more": False,
            }
        elif step == "logout":
            response_payload = None
        return JourneyResponse(
            JourneyResult(step, 10.0, status, 100, True, None),
            response_payload,
        )

    def close(self) -> None:
        self.closed = True


class FakeMailCodeClient:
    def __init__(self, code: str = "123456") -> None:
        self.code = code
        self.closed = False

    def wait_for_code(self, email: str) -> MailCodeResponse:
        assert email.endswith("@example.test")
        return MailCodeResponse(
            JourneyResult(MAIL_DELIVERY_STEP, 50.0, 200, 120, True, None),
            self.code,
        )

    def close(self) -> None:
        self.closed = True


class FakeMailpitResponse:
    def __init__(self, status: int, body: bytes) -> None:
        self.status = status
        self.body = body

    def read(self, amount: int | None = None) -> bytes:
        del amount
        return self.body


class FakeMailpitConnection:
    def __init__(self, responses: list[FakeMailpitResponse]) -> None:
        self.responses = responses
        self.targets: list[str] = []

    def request(
        self,
        method: str,
        target: str,
        *,
        headers: dict[str, str],
    ) -> None:
        del method, headers
        self.targets.append(target)

    def getresponse(self) -> FakeMailpitResponse:
        return self.responses.pop(0)

    def close(self) -> None:
        return None


class RegisteredCapacityTests(unittest.TestCase):
    def test_mailpit_client_polls_exact_recipient_and_extracts_code(self) -> None:
        connection = FakeMailpitConnection(
            [
                FakeMailpitResponse(404, b""),
                FakeMailpitResponse(200, b"Your one-time code is 654321."),
            ]
        )
        client = MailpitHttpClient(
            base_url="http://127.0.0.1:18025",
            request_timeout_seconds=1,
            delivery_timeout_seconds=1,
            poll_interval_seconds=0,
        )
        client.connection = connection

        response = client.wait_for_code("load-user@example.test")

        self.assertTrue(response.result.successful, response.result.error)
        self.assertEqual(response.code, "654321")
        self.assertEqual(len(connection.targets), 2)
        self.assertIn("load-user%40example.test", connection.targets[-1])

    def test_registered_journey_verifies_email_syncs_refreshes_and_logs_out(
        self,
    ) -> None:
        client = FakeRegisteredJourneyClient()
        mail_client = FakeMailCodeClient()
        remaining = 2

        def claim(amount: int) -> bool:
            nonlocal remaining
            if amount > remaining:
                return False
            remaining -= amount
            return True

        summary = run_registered_user_journey(
            client,
            mail_client,
            config=RegisteredStageConfig(
                deadline=float("inf"),
                run_tag="abcd1234",
                email_domain="example.test",
                edition="madani-hafs",
                operations_per_push=1,
                max_cycles_per_user=2,
                refresh_every_cycles=2,
                think_time_seconds=0,
                claim_sync_operations=claim,
            ),
        )

        self.assertTrue(summary.bootstrapped)
        self.assertTrue(summary.registered)
        self.assertEqual(summary.cycles_completed, 2)
        self.assertEqual(summary.sync_operations_completed, 2)
        self.assertEqual(summary.refreshes_completed, 1)
        self.assertTrue(summary.hit_cycle_cap)
        self.assertEqual(
            client.steps,
            [
                "guest-bootstrap",
                "email-start",
                "email-verify",
                "registered-session",
                "sync-push",
                "sync-pull",
                "sync-push",
                "sync-pull",
                "token-refresh",
                "logout",
            ],
        )

    def test_thresholds_fail_when_registration_or_delivery_is_incomplete(self) -> None:
        summary = RegisteredStageSummary(
            stage=StageSpec(2, 60),
            results=(
                JourneyResult("guest-bootstrap", 10, 200, 10, True, None),
                JourneyResult(
                    MAIL_DELIVERY_STEP,
                    6000,
                    404,
                    0,
                    False,
                    "mailpit_code_timeout",
                ),
            ),
            elapsed_seconds=1,
            stop_reason="journey_ended",
            users_bootstrapped=1,
            users_registered=0,
            cycles_completed=0,
            sync_operations_completed=0,
            refreshes_completed=0,
        )

        failures = threshold_failures(
            summary,
            max_error_rate=0.01,
            max_p95_ms=750,
            max_p99_ms=1500,
            max_email_delivery_p95_ms=5000,
        )
        payload = stage_payload(summary, failures)

        self.assertTrue(any("registered" in failure for failure in failures))
        self.assertTrue(any("email delivery" in failure for failure in failures))
        self.assertFalse(payload["passed"])
        self.assertEqual(
            payload["steps"][MAIL_DELIVERY_STEP]["errors_by_reason"],
            {"mailpit_code_timeout": 1},
        )

    def test_registered_target_requires_all_confirmations_and_loopback_mailpit(
        self,
    ) -> None:
        values = {
            "base_url": "https://staging.example.test",
            "confirmed_host": "staging.example.test",
            "allow_stateful_writes": True,
            "confirm_disposable_staging_data": True,
            "allow_email_challenges": True,
            "confirm_intercepted_test_email": True,
            "mailpit_url": "http://127.0.0.1:18025",
            "email_domain": "example.test",
        }
        validate_registered_authorization(**values)
        for overrides in (
            {"allow_email_challenges": False},
            {"confirm_intercepted_test_email": False},
            {"mailpit_url": "https://mail.example.test"},
            {"email_domain": "example.com"},
        ):
            with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                validate_registered_authorization(**{**values, **overrides})

    def test_registered_inputs_are_strictly_bounded(self) -> None:
        self.assertEqual(bounded_stage("20:600"), StageSpec(20, 600.0))
        self.assertEqual(
            validate_mailpit_url("http://localhost:8025"), "http://localhost:8025"
        )
        self.assertEqual(
            validate_test_email_domain("load.example.test"), "load.example.test"
        )
        for value in ("21:60", "1:601"):
            with (
                self.subTest(value=value),
                self.assertRaises(argparse.ArgumentTypeError),
            ):
                bounded_stage(value)
        for value in ("https://mail.example.test", "file:///tmp/mail"):
            with (
                self.subTest(value=value),
                self.assertRaises(argparse.ArgumentTypeError),
            ):
                validate_mailpit_url(value)
        with self.assertRaises(argparse.ArgumentTypeError):
            validate_test_email_domain("example.com")


if __name__ == "__main__":
    unittest.main()

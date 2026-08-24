from __future__ import annotations

import argparse
import unittest
import uuid
from typing import Any

from ops.load.capacity import StageSpec
from ops.load.sync_capacity import (
    JourneyCredentials,
    JourneyResponse,
    JourneyResult,
    StatefulHttpClient,
    SyncRunConfig,
    SyncStageConfig,
    SyncStageSummary,
    _bootstrap_payload,
    _credentials,
    _sync_push_payload,
    bounded_stage,
    run_sync_stage,
    run_user_journey,
    stage_payload,
    threshold_failures,
    validate_stateful_authorization,
)


class FakeJourneyClient:
    def __init__(self) -> None:
        self.revision = 0
        self.cursor = 0
        self.closed = False
        self.steps: list[str] = []

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
                        "cursor": self.cursor,
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


class FakeHttpResponse:
    status = 200

    def read(self, amount: int | None = None) -> bytes:
        del amount
        return b'{"access_token":"access","refresh_token":"refresh"}'


class FakeHttpConnection:
    def __init__(self) -> None:
        self.request_args: tuple[str, str, bytes | None, dict[str, str]] | None = None

    def request(
        self,
        method: str,
        target: str,
        *,
        body: bytes | None,
        headers: dict[str, str],
    ) -> None:
        self.request_args = (method, target, body, headers)

    def getresponse(self) -> FakeHttpResponse:
        return FakeHttpResponse()

    def close(self) -> None:
        return None


class SyncCapacityTests(unittest.TestCase):
    def test_http_client_keeps_credentials_out_of_url_and_requests_identity_json(self) -> None:
        connection = FakeHttpConnection()
        client = StatefulHttpClient(
            base_url="https://staging.example.test/prefix",
            timeout_seconds=1,
        )
        client.connection = connection

        response = client.request(
            step="token-refresh",
            method="POST",
            path="/api/v1/auth/token/refresh",
            payload={"refresh_token": "sensitive-refresh"},
        )

        self.assertTrue(response.result.successful, response.result.error)
        self.assertIsNotNone(connection.request_args)
        assert connection.request_args is not None
        method, target, body, headers = connection.request_args
        self.assertEqual(method, "POST")
        self.assertEqual(target, "/prefix/api/v1/auth/token/refresh")
        self.assertNotIn("sensitive-refresh", target)
        self.assertIn(b"sensitive-refresh", body or b"")
        self.assertEqual(headers["Accept-Encoding"], "identity")

    def test_generated_bootstrap_secrets_are_not_fixed_or_short(self) -> None:
        first = _bootstrap_payload("abcd1234")
        second = _bootstrap_payload("abcd1234")

        self.assertNotEqual(first["installation_id"], second["installation_id"])
        self.assertNotEqual(first["installation_credential"], second["installation_credential"])
        self.assertGreaterEqual(len(str(first["installation_credential"])), 43)
        self.assertEqual(first["app_version"], "load.abcd1234")

    def test_sync_batch_predicts_revisions_without_uuid7_requirement(self) -> None:
        payload = _sync_push_payload(
            entity_id=uuid.uuid4(),
            edition="madani-hafs",
            base_revision=4,
            operations_per_push=3,
            cycle=2,
        )
        operations = payload["operations"]

        assert isinstance(operations, list)
        self.assertEqual([row["base_revision"] for row in operations], [4, 5, 6])
        self.assertTrue(all(row["entity_type"] == "reading_position" for row in operations))

    def test_credentials_require_both_tokens(self) -> None:
        result = JourneyResult("auth", 1, 200, 10, True, None)

        self.assertEqual(
            _credentials(
                JourneyResponse(
                    result,
                    {"access_token": "access", "refresh_token": "refresh"},
                )
            ),
            JourneyCredentials("access", "refresh"),
        )
        self.assertIsNone(_credentials(JourneyResponse(result, {"access_token": "access"})))

    def test_user_journey_pushes_pulls_refreshes_and_logs_out(self) -> None:
        client = FakeJourneyClient()
        remaining = 4

        def claim(amount: int) -> bool:
            nonlocal remaining
            if amount > remaining:
                return False
            remaining -= amount
            return True

        summary = run_user_journey(
            client,
            config=SyncStageConfig(
                deadline=float("inf"),
                run_tag="abcd1234",
                edition="madani-hafs",
                operations_per_push=2,
                max_cycles_per_user=2,
                refresh_every_cycles=2,
                think_time_seconds=0,
                claim_sync_operations=claim,
            ),
        )

        self.assertTrue(summary.bootstrapped)
        self.assertEqual(summary.cycles_completed, 2)
        self.assertEqual(summary.sync_operations_completed, 4)
        self.assertEqual(summary.refreshes_completed, 1)
        self.assertTrue(summary.hit_cycle_cap)
        self.assertEqual(
            client.steps,
            [
                "guest-bootstrap",
                "current-session",
                "sync-push",
                "sync-pull",
                "sync-push",
                "sync-pull",
                "token-refresh",
                "logout",
            ],
        )

    def test_stage_respects_global_sync_operation_cap(self) -> None:
        summary = run_sync_stage(
            stage=StageSpec(2, 10),
            client_factory=FakeJourneyClient,
            config=SyncRunConfig(
                run_tag="abcd1234",
                edition="madani-hafs",
                operations_per_push=1,
                max_cycles_per_user=100,
                refresh_every_cycles=20,
                think_time_seconds=0,
                max_sync_operations=3,
            ),
        )

        self.assertEqual(summary.stop_reason, "sync_operation_cap")
        self.assertEqual(summary.sync_operations_completed, 3)
        self.assertEqual(summary.users_bootstrapped, 2)

    def test_thresholds_and_report_fail_for_incomplete_stage(self) -> None:
        result = JourneyResult("sync-push", 900, 500, 100, False, "unexpected_status_500")
        summary = SyncStageSummary(
            stage=StageSpec(2, 60),
            results=(result,),
            elapsed_seconds=1,
            stop_reason="journey_ended",
            users_bootstrapped=1,
            cycles_completed=0,
            sync_operations_completed=0,
            refreshes_completed=0,
        )

        failures = threshold_failures(
            summary,
            max_error_rate=0.01,
            max_p95_ms=750,
            max_p99_ms=800,
        )
        payload = stage_payload(summary, failures)

        self.assertTrue(any("duration" in failure for failure in failures))
        self.assertTrue(any("bootstrapped" in failure for failure in failures))
        self.assertTrue(any("push/pull" in failure for failure in failures))
        self.assertEqual(
            payload["steps"]["sync-push"]["errors_by_reason"],
            {"unexpected_status_500": 1},
        )
        self.assertFalse(payload["passed"])

    def test_stateful_target_requires_all_exact_confirmations(self) -> None:
        validate_stateful_authorization(
            base_url="https://staging.example.test",
            confirmed_host="staging.example.test",
            allow_stateful_writes=True,
            confirm_disposable_staging_data=True,
        )
        for overrides in (
            {"confirmed_host": "production.example.test"},
            {"allow_stateful_writes": False},
            {"confirm_disposable_staging_data": False},
        ):
            values = {
                "base_url": "https://staging.example.test",
                "confirmed_host": "staging.example.test",
                "allow_stateful_writes": True,
                "confirm_disposable_staging_data": True,
                **overrides,
            }
            with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                validate_stateful_authorization(**values)

    def test_stateful_stage_has_stricter_bounds(self) -> None:
        self.assertEqual(bounded_stage("100:900"), StageSpec(100, 900.0))
        for value in ("101:1", "1:901"):
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                bounded_stage(value)


if __name__ == "__main__":
    unittest.main()

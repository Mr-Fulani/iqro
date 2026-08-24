from __future__ import annotations

import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from ops.observability.render_config import ROOT, ConfigurationError, render


class RenderConfigTests(unittest.TestCase):
    def environment(self) -> dict[str, str]:
        return {
            "QURAN_OPERATIONS_TOKEN": "o" * 40,
            "OBSERVABILITY_MONTHLY_BUDGET_USD": "125.50",
            "OBSERVABILITY_MONTHLY_ORIGIN_EGRESS_BUDGET_BYTES": "107374182400",
        }

    def test_render_writes_budgets_without_leaking_secrets(self) -> None:
        environment = self.environment() | {
            "OBSERVABILITY_ALERT_WEBHOOK_URL": "https://alerts.example.test/quran"
        }
        with tempfile.TemporaryDirectory() as temporary_directory:
            output = Path(temporary_directory)
            with patch.dict(os.environ, environment, clear=True):
                render(output)

            rules = (output / "rules.yml").read_text(encoding="utf-8")
            assert "vector(125.5)" in rules
            assert "vector(107374182400)" in rules
            assert "operations-token" in (output / "prometheus.yml").read_text(encoding="utf-8")
            combined_config = "".join(
                path.read_text(encoding="utf-8")
                for path in output.iterdir()
                if path.name not in {"operations-token", "alert-webhook-url"}
            )
            assert "o" * 40 not in combined_config
            assert "https://alerts.example.test/quran" not in combined_config
            assert stat.S_IMODE((output / "operations-token").stat().st_mode) == stat.S_IRUSR
            assert stat.S_IMODE((output / "alert-webhook-url").stat().st_mode) == stat.S_IRUSR

            with patch.dict(os.environ, self.environment(), clear=True):
                render(output)
            assert not (output / "alert-webhook-url").exists()
            assert "receiver: unconfigured" in (output / "alertmanager.yml").read_text(
                encoding="utf-8"
            )

    def test_render_rejects_invalid_budget(self) -> None:
        environment = self.environment() | {"OBSERVABILITY_MONTHLY_BUDGET_USD": "replace-me"}
        expected_error = self.assertRaisesRegex(ConfigurationError, "positive decimal")  # noqa: PT027
        with (
            tempfile.TemporaryDirectory() as temporary_directory,
            patch.dict(os.environ, environment, clear=True),
            expected_error,
        ):
            render(Path(temporary_directory))

    def test_dashboard_json_is_valid(self) -> None:
        dashboard = json.loads(
            (ROOT / "grafana" / "dashboards" / "quran-platform-overview.json").read_text(
                encoding="utf-8"
            )
        )

        assert dashboard["uid"] == "quran-platform-overview"
        assert len(dashboard["panels"]) >= 10


if __name__ == "__main__":
    unittest.main()

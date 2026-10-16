from __future__ import annotations

import pytest
from django.core.exceptions import ImproperlyConfigured

from quran_backend.error_reporting import sentry_options


def test_error_reporting_is_off_without_a_dsn() -> None:
    assert sentry_options({}, release="1.2.3") is None
    assert sentry_options({"SENTRY_DSN": "  "}, release="1.2.3") is None


def test_reports_carry_no_personal_data_or_request_bodies() -> None:
    options = sentry_options(
        {"SENTRY_DSN": "https://key@o1.ingest.de.sentry.io/2", "SENTRY_ENVIRONMENT": "staging"},
        release="1.2.3",
    )

    assert options == {
        "dsn": "https://key@o1.ingest.de.sentry.io/2",
        "environment": "staging",
        "release": "quran-platform-backend@1.2.3",
        "send_default_pii": False,
        "max_request_body_size": "never",
        "traces_sample_rate": 0.0,
    }


@pytest.mark.parametrize("rate", ["often", "1.5", "-0.1"])
def test_invalid_trace_sample_rate_is_rejected(rate: str) -> None:
    with pytest.raises(ImproperlyConfigured, match="SENTRY_TRACES_SAMPLE_RATE"):
        sentry_options(
            {
                "SENTRY_DSN": "https://key@o1.ingest.de.sentry.io/2",
                "SENTRY_TRACES_SAMPLE_RATE": rate,
            },
            release="1",
        )

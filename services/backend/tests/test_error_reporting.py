from __future__ import annotations

import asyncio
import logging

import pytest
from django.core.exceptions import ImproperlyConfigured

from quran_backend.error_reporting import (
    drop_cancelled_requests,
    drop_telegram_breadcrumb,
    drop_telegram_spans,
    sentry_options,
)


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
        "before_send": drop_cancelled_requests,
        "before_breadcrumb": drop_telegram_breadcrumb,
        "before_send_transaction": drop_telegram_spans,
    }


def test_requests_to_telegram_never_reach_sentry() -> None:
    telegram = {"category": "httplib", "data": {"url": "https://api.telegram.org/bot1:x/send"}}
    other = {"category": "httplib", "data": {"url": "https://example.test/"}}

    assert drop_telegram_breadcrumb(telegram, {}) is None
    assert drop_telegram_breadcrumb(other, {}) == other
    event = {
        "spans": [
            {"description": "POST https://api.telegram.org/bot1:x/sendMessage"},
            {"description": "GET https://example.test/"},
        ]
    }
    assert drop_telegram_spans(event, {})["spans"] == [{"description": "GET https://example.test/"}]


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


def test_a_client_hanging_up_is_not_a_sentry_event() -> None:
    cancelled = asyncio.CancelledError()
    hung_up = logging.LogRecord(
        "asyncio",
        logging.ERROR,
        __file__,
        1,
        "CancelledError exception in shielded future",
        None,
        (asyncio.CancelledError, cancelled, None),
    )
    other = logging.LogRecord("asyncio", logging.ERROR, __file__, 1, "Task exception", None, None)
    event = {"logger": "asyncio"}

    assert drop_cancelled_requests(event, {"log_record": hung_up}) is None
    assert drop_cancelled_requests(event, {"log_record": other}) is event
    assert drop_cancelled_requests(event, {}) is event

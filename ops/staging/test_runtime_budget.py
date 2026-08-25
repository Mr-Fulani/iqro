from __future__ import annotations

from pathlib import Path

from ops.staging.verify_runtime_budget import (
    ResourceLimits,
    compare_runtime,
    load_expected_limits,
    parse_memory_bytes,
    parse_nano_cpus,
)


def test_budget_overlay_contains_expected_long_running_services() -> None:
    limits = load_expected_limits(Path("compose.staging.budget.yaml"))

    assert limits["backend"] == ResourceLimits(650_000_000, 512 * 1024**2)
    assert limits["web"] == ResourceLimits(500_000_000, 448 * 1024**2)
    assert limits["postgres"] == ResourceLimits(750_000_000, 640 * 1024**2)
    assert limits["tls-proxy"] == ResourceLimits(100_000_000, 64 * 1024**2)


def test_compare_runtime_allows_multiple_matching_replicas() -> None:
    expected = {"backend": ResourceLimits(650_000_000, 512 * 1024**2)}
    actual = {"backend": [expected["backend"], expected["backend"]]}

    assert compare_runtime(expected, actual) == []


def test_compare_runtime_rejects_missing_and_drifted_services() -> None:
    expected = {
        "backend": ResourceLimits(650_000_000, 512 * 1024**2),
        "web": ResourceLimits(500_000_000, 448 * 1024**2),
    }
    actual = {"backend": [ResourceLimits(2_000_000_000, 1024 * 1024**2)]}

    errors = compare_runtime(expected, actual)

    assert any("backend[1]: NanoCPUs" in error for error in errors)
    assert any("backend[1]: memory" in error for error in errors)
    assert "web: no running Compose container found" in errors


def test_resource_parsers_are_binary_and_exact() -> None:
    assert parse_memory_bytes("384m") == 384 * 1024**2
    assert parse_memory_bytes('"1g"') == 1024**3
    assert parse_nano_cpus("0.15") == 150_000_000

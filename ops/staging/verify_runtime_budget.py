from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any

try:
    from ops.staging.preflight import load_env
except (
    ModuleNotFoundError
):  # Direct execution: python ops/staging/verify_runtime_budget.py
    from preflight import load_env


LONG_RUNNING_SERVICES = frozenset(
    {
        "postgres",
        "redis",
        "backend",
        "worker",
        "beat",
        "web",
        "gateway",
        "mailpit",
        "tls-proxy",
    }
)
PROJECT_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
MEMORY_PATTERN = re.compile(r"^(\d+)([kmgt]?)$", re.IGNORECASE)


@dataclass(frozen=True, slots=True)
class ResourceLimits:
    nano_cpus: int
    memory_bytes: int


def parse_memory_bytes(value: str) -> int:
    normalized = value.strip().strip('"').strip("'")
    match = MEMORY_PATTERN.fullmatch(normalized)
    if match is None:
        raise ValueError(f"unsupported memory limit: {value}")
    amount = int(match.group(1))
    multiplier = {
        "": 1,
        "k": 1024,
        "m": 1024**2,
        "g": 1024**3,
        "t": 1024**4,
    }[match.group(2).lower()]
    return amount * multiplier


def parse_nano_cpus(value: str) -> int:
    try:
        cpus = Decimal(value.strip().strip('"').strip("'"))
    except InvalidOperation as exc:
        raise ValueError(f"unsupported CPU limit: {value}") from exc
    if cpus <= 0:
        raise ValueError("CPU limit must be positive")
    nano_cpus = cpus * Decimal(1_000_000_000)
    if nano_cpus != nano_cpus.to_integral_value():
        raise ValueError("CPU limit must resolve to whole NanoCPUs")
    return int(nano_cpus)


def load_expected_limits(path: Path) -> dict[str, ResourceLimits]:
    current_service: str | None = None
    values: dict[str, dict[str, str]] = {}
    in_services = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].rstrip()
        if not line:
            continue
        if line == "services:":
            in_services = True
            current_service = None
            continue
        if not in_services:
            continue
        service_match = re.fullmatch(r"  ([A-Za-z0-9_-]+):", line)
        if service_match:
            current_service = service_match.group(1)
            values.setdefault(current_service, {})
            continue
        if line and not line.startswith(" "):
            break
        if current_service is None:
            continue
        setting_match = re.fullmatch(r"    (cpus|mem_limit):\s*(.+)", line)
        if setting_match:
            values[current_service][setting_match.group(1)] = setting_match.group(
                2
            ).strip()

    expected: dict[str, ResourceLimits] = {}
    for service in sorted(LONG_RUNNING_SERVICES):
        service_values = values.get(service, {})
        if "cpus" not in service_values or "mem_limit" not in service_values:
            raise ValueError(f"{path}: missing cpus/mem_limit for {service}")
        expected[service] = ResourceLimits(
            nano_cpus=parse_nano_cpus(service_values["cpus"]),
            memory_bytes=parse_memory_bytes(service_values["mem_limit"]),
        )
    return expected


def compare_runtime(
    expected: dict[str, ResourceLimits],
    actual: dict[str, list[ResourceLimits]],
) -> list[str]:
    errors: list[str] = []
    for service, expected_limits in sorted(expected.items()):
        replicas = actual.get(service, [])
        if not replicas:
            errors.append(f"{service}: no running Compose container found")
            continue
        for index, actual_limits in enumerate(replicas, start=1):
            if actual_limits.nano_cpus != expected_limits.nano_cpus:
                errors.append(
                    f"{service}[{index}]: NanoCPUs {actual_limits.nano_cpus} != "
                    f"{expected_limits.nano_cpus}"
                )
            if actual_limits.memory_bytes != expected_limits.memory_bytes:
                errors.append(
                    f"{service}[{index}]: memory {actual_limits.memory_bytes} != "
                    f"{expected_limits.memory_bytes}"
                )
    return errors


def _run(command: list[str]) -> str:
    completed = subprocess.run(
        command,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout


def inspect_runtime(
    project_name: str, services: set[str]
) -> dict[str, list[ResourceLimits]]:
    actual: dict[str, list[ResourceLimits]] = {}
    for service in sorted(services):
        ids = [
            line.strip()
            for line in _run(
                [
                    "docker",
                    "ps",
                    "--filter",
                    f"label=com.docker.compose.project={project_name}",
                    "--filter",
                    f"label=com.docker.compose.service={service}",
                    "--format",
                    "{{.ID}}",
                ]
            ).splitlines()
            if line.strip()
        ]
        replicas: list[ResourceLimits] = []
        for container_id in ids:
            raw_host_config = _run(
                [
                    "docker",
                    "inspect",
                    "--format",
                    "{{json .HostConfig}}",
                    container_id,
                ]
            )
            host_config: dict[str, Any] = json.loads(raw_host_config)
            replicas.append(
                ResourceLimits(
                    nano_cpus=int(host_config.get("NanoCpus") or 0),
                    memory_bytes=int(host_config.get("Memory") or 0),
                )
            )
        actual[service] = replicas
    return actual


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Fail when running staging containers drift from the budget overlay."
    )
    parser.add_argument(
        "--env-file", type=Path, default=Path("ops/staging/staging.env")
    )
    parser.add_argument(
        "--compose-file",
        type=Path,
        default=Path("compose.staging.budget.yaml"),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        env_values, env_errors = load_env(args.env_file)
        if env_errors:
            raise ValueError("invalid staging env: " + "; ".join(env_errors))
        project_name = env_values.get("COMPOSE_PROJECT_NAME", "")
        if not PROJECT_PATTERN.fullmatch(project_name):
            raise ValueError("COMPOSE_PROJECT_NAME is missing or invalid")
        expected = load_expected_limits(args.compose_file)
        actual = inspect_runtime(project_name, set(expected))
        errors = compare_runtime(expected, actual)
    except (
        OSError,
        ValueError,
        json.JSONDecodeError,
        subprocess.SubprocessError,
    ) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    replica_summary = ", ".join(
        f"{service}={len(actual[service])}" for service in sorted(actual)
    )
    print(f"OK: staging runtime matches budget overlay ({replica_summary}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

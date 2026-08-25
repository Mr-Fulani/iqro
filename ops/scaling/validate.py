#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections.abc import Sequence

MAX_SINGLE_HOST_REPLICAS = 64


def parse_replica_count(value: str) -> int:
    try:
        replicas = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("replica count must be an integer") from exc
    if replicas < 1:
        raise argparse.ArgumentTypeError("replica count must be at least 1")
    if replicas > MAX_SINGLE_HOST_REPLICAS:
        raise argparse.ArgumentTypeError(
            f"replica count must not exceed {MAX_SINGLE_HOST_REPLICAS}"
        )
    return replicas


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate bounded single-host web/API replica counts."
    )
    parser.add_argument("--api-replicas", required=True, type=parse_replica_count)
    parser.add_argument("--web-replicas", required=True, type=parse_replica_count)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    print(
        "OK: bounded scale request validated; "
        f"api_replicas={args.api_replicas} web_replicas={args.web_replicas}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

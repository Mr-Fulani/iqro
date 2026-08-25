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


def validate_replica_plan(
    *,
    api_replicas: int,
    web_replicas: int,
    max_api_replicas: int,
    max_web_replicas: int,
) -> None:
    if api_replicas > max_api_replicas:
        raise argparse.ArgumentTypeError(
            f"API replica count must not exceed profile limit {max_api_replicas}"
        )
    if web_replicas > max_web_replicas:
        raise argparse.ArgumentTypeError(
            f"web replica count must not exceed profile limit {max_web_replicas}"
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate bounded single-host web/API replica counts."
    )
    parser.add_argument("--api-replicas", required=True, type=parse_replica_count)
    parser.add_argument("--web-replicas", required=True, type=parse_replica_count)
    parser.add_argument(
        "--max-api-replicas",
        type=parse_replica_count,
        default=MAX_SINGLE_HOST_REPLICAS,
    )
    parser.add_argument(
        "--max-web-replicas",
        type=parse_replica_count,
        default=MAX_SINGLE_HOST_REPLICAS,
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        validate_replica_plan(
            api_replicas=args.api_replicas,
            web_replicas=args.web_replicas,
            max_api_replicas=args.max_api_replicas,
            max_web_replicas=args.max_web_replicas,
        )
    except argparse.ArgumentTypeError as exc:
        parser.error(str(exc))
    print(
        "OK: bounded scale request validated; "
        f"api_replicas={args.api_replicas} web_replicas={args.web_replicas} "
        f"max_api_replicas={args.max_api_replicas} "
        f"max_web_replicas={args.max_web_replicas}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
from pathlib import Path


def main() -> None:
    source_dir = Path(__file__).resolve().parent / "src"
    sys.path.insert(0, str(source_dir))
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "quran_backend.settings.local")

    from django.core.management import execute_from_command_line  # noqa: PLC0415

    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()

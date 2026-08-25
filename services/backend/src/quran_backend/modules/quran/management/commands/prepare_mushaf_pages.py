from __future__ import annotations

from pathlib import Path
from typing import Any

from django.core.management.base import BaseCommand, CommandError, CommandParser

from quran_backend.modules.quran.mushaf_assets import (
    DEFAULT_VARIANT_WIDTHS,
    KNOWN_SOURCE_SHA256,
    MushafAssetError,
    PopplerWebpRenderer,
    build_mushaf_assets,
    create_build_plan,
    inspect_mushaf_source,
    load_mushaf_asset_build_spec,
)


class Command(BaseCommand):
    help = (
        "Validate a pinned Mushaf PDF and prepare immutable WebP page assets. "
        "This command never imports or publishes Quran content."
    )

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("source", type=Path, help="Path to the pinned source PDF.")
        parser.add_argument(
            "--output",
            type=Path,
            help="Fresh output directory. Required unless --validate-only is used.",
        )
        parser.add_argument(
            "--expected-sha256",
            help=(
                "Pinned SHA-256 for the legacy Hafs profile. Defaults to its known checksum; "
                "cannot be combined with --spec."
            ),
        )
        parser.add_argument(
            "--spec",
            type=Path,
            help="Edition-specific Mushaf PDF build spec.",
        )
        parser.add_argument("--first-page", type=int, default=1, help="First logical page.")
        parser.add_argument(
            "--last-page",
            type=int,
            default=None,
            help="Last logical page, inclusive.",
        )
        parser.add_argument(
            "--variant-width",
            action="append",
            type=int,
            dest="variant_widths",
            help="WebP width in pixels; repeat for multiple variants (default: 480/900/1800).",
        )
        mode = parser.add_mutually_exclusive_group()
        mode.add_argument(
            "--validate-only",
            action="store_true",
            help="Validate source integrity and PDF structure without creating output.",
        )
        mode.add_argument(
            "--dry-run",
            action="store_true",
            help="Validate source, tools and build plan without creating output.",
        )

    def handle(self, *args: Any, **options: Any) -> None:  # noqa: ARG002
        try:
            if options["spec"] is not None and options["expected_sha256"] is not None:
                raise MushafAssetError("--spec and --expected-sha256 cannot be combined.")
            if options["spec"] is None:
                source = inspect_mushaf_source(
                    options["source"],
                    expected_sha256=options["expected_sha256"] or KNOWN_SOURCE_SHA256,
                )
            else:
                source = inspect_mushaf_source(
                    options["source"],
                    build_spec=load_mushaf_asset_build_spec(options["spec"]),
                )
            logical_page_count = source.build_spec.logical_page_count
            self.stdout.write(
                self.style.SUCCESS(
                    f"Source is valid: {source.pdf_page_count} PDF pages, "
                    f"{logical_page_count} logical pages, SHA-256 {source.sha256}."
                )
            )
            if options["validate_only"]:
                return

            output: Path | None = options["output"]
            if output is None:
                raise MushafAssetError("--output is required for build and dry-run modes.")
            widths = options["variant_widths"] or list(DEFAULT_VARIANT_WIDTHS)
            plan = create_build_plan(
                source,
                output,
                first_logical_page=options["first_page"],
                last_logical_page=options["last_page"],
                variant_widths=widths,
            )
            renderer = PopplerWebpRenderer()
            if options["dry_run"]:
                tools = ", ".join(
                    f"{name}={version}" for name, version in renderer.tool_metadata().items()
                )
                self.stdout.write(
                    self.style.SUCCESS(
                        f"Dry run is valid: {plan.page_count} pages, {plan.asset_count} assets, "
                        f"output {plan.output}. Tools: {tools}. No files were created."
                    )
                )
                return

            result = build_mushaf_assets(
                plan,
                renderer=renderer,
                progress=self._report_progress,
            )
        except MushafAssetError as exc:
            raise CommandError(str(exc)) from exc

        self.stdout.write(
            self.style.SUCCESS(
                f"Prepared {result.asset_count} immutable assets in {result.output}. "
                "No content was imported or published."
            )
        )

    def _report_progress(self, completed: int, total: int) -> None:
        if completed in (1, total) or completed % 10 == 0:
            self.stdout.write(f"Rendered {completed}/{total} logical pages.")

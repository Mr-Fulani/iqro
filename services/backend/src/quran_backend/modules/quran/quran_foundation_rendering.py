_QCF_V2_FONT_TEMPLATE = "https://verses.quran.foundation/fonts/quran/hafs/v2/woff2/p{page}.woff2"
_QPC_HAFS_FONT_URL = (
    "https://verses.quran.foundation/fonts/quran/hafs/uthmanic_hafs/UthmanicHafs1Ver18.woff2"
)
_QCF_V4_TAJWEED_FONT_TEMPLATE = (
    "https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/woff2/p{page}.woff2"
)


def quran_foundation_rendering(
    source_id: int,
    *,
    page_number: int | None = None,
) -> dict[str, object]:
    """Return a client-safe rendering contract for a synced Quran.Foundation Mushaf."""
    if source_id == 1:
        return _font_rendering(
            mode="page-font",
            font_url_template=_QCF_V2_FONT_TEMPLATE,
            page_number=page_number,
            color_format=None,
        )
    if source_id == 5:
        return {
            "available": True,
            "mode": "unicode-font",
            "font_format": "woff2",
            "font_url": _QPC_HAFS_FONT_URL,
        }
    if source_id == 19:
        return _font_rendering(
            mode="page-font",
            font_url_template=_QCF_V4_TAJWEED_FONT_TEMPLATE,
            page_number=page_number,
            color_format="COLRv1",
        )
    if source_id == 11:
        return {
            "available": False,
            "mode": "word-images",
            "reason": "official_asset_base_url_unavailable",
        }
    return {
        "available": False,
        "mode": "unknown",
        "reason": "unsupported_mushaf",
    }


def _font_rendering(
    *,
    mode: str,
    font_url_template: str,
    page_number: int | None,
    color_format: str | None,
) -> dict[str, object]:
    result: dict[str, object] = {
        "available": True,
        "mode": mode,
        "font_format": "woff2",
        "font_url_template": font_url_template,
    }
    if page_number is not None:
        result["font_url"] = font_url_template.format(page=page_number)
    if color_format is not None:
        result["color_format"] = color_format
    return result

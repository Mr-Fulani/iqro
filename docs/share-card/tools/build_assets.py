#!/usr/bin/env python3
"""Prepares the share card's files for the app and the site from the owner's
masters: 1080 px backgrounds in three fabric colours, the layout and the fonts.

    python3 docs/share-card/tools/build_assets.py

Needs Pillow and numpy. Run from the repository root after changing a master
or layout.json; the output is committed.
"""
import colorsys
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SPEC = ROOT / "docs/share-card"
APP = ROOT / "clients/iqro_mobile/assets/share_card"
WEB = ROOT / "services/web/public/share-card"

FORMATS = {"story": ("frame-9x16.webp", (1080, 1920)), "post": ("frame-4x5.webp", (1080, 1350))}
# Hue shift (turns), saturation and value factors of the fabric; the ivory
# relief keeps its colour. Emerald is the master as generated.
COLOURS = {"emerald": (0.0, 1.0, 1.0), "turquoise": (0.0, 0.62, 1.38), "midnight": (0.135, 0.72, 0.98)}


def recolour(image: Image.Image, shift: float, saturation: float, value: float) -> Image.Image:
    if (shift, saturation, value) == (0.0, 1.0, 1.0):
        return image
    hsv = np.asarray(image.convert("HSV"), dtype=np.float32) / 255.0
    hue, sat, val = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    # The fabric is green (hue .35–.6); the relief is ivory (hue about .1).
    # The weight fades between them so edges and shadows stay smooth.
    weight = np.clip((hue - 0.22) / 0.12, 0.0, 1.0) * np.clip(sat / 0.25, 0.0, 1.0)
    hue = (hue + shift * weight) % 1.0
    sat = np.clip(sat * (1 + (saturation - 1) * weight), 0.0, 1.0)
    val = np.clip(val * (1 + (value - 1) * weight), 0.0, 1.0)
    out = np.stack([hue, sat, val], axis=-1)
    return Image.fromarray((out * 255).round().astype(np.uint8), "HSV").convert("RGB")


def main() -> None:
    for target in (APP, WEB):
        target.mkdir(parents=True, exist_ok=True)
    for name, (master, size) in FORMATS.items():
        base = Image.open(SPEC / "masters" / master).convert("RGB").resize(size, Image.LANCZOS)
        for colour, factors in COLOURS.items():
            picture = recolour(base, *factors)
            picture.save(APP / f"{name}-{colour}.webp", "WEBP", quality=86, method=6)
            shutil.copyfile(APP / f"{name}-{colour}.webp", WEB / f"{name}-{colour}.webp")
    shutil.copyfile(SPEC / "layout.json", APP / "layout.json")
    shutil.copyfile(SPEC / "layout.json", ROOT / "services/web/lib/share-card-layout.json")
    fonts = ROOT / "clients/iqro_mobile/assets/fonts"
    for font in ("PTSerif-Regular.ttf", "AmiriQuran-Regular.ttf"):
        shutil.copyfile(fonts / font, WEB / font)


if __name__ == "__main__":
    main()

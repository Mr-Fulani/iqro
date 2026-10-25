"""Derive web and notification artwork from the installed IQRO seal.

Run with Python and Pillow from any directory. Launcher icons are untouched.
"""

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter


MOBILE = Path(__file__).resolve().parents[1]
WEB = MOBILE.parents[1] / "services/web"
RES = MOBILE / "android/app/src/main/res/drawable-nodpi"
SOURCE = Image.open(MOBILE / "assets/brand/iqro-logo.png").convert("RGBA")
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--mobile-only", action="store_true")
args = parser.parse_args()


def square(size):
    artwork = SOURCE.copy()
    artwork.thumbnail((size, size), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size))
    canvas.alpha_composite(artwork, ((size - artwork.width) // 2, (size - artwork.height) // 2))
    return canvas


if not args.mobile_only:
    square(512).save(WEB / "public/iqro-app-icon.png")
    square(256).save(WEB / "app/favicon.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
    apple = Image.new("RGB", (180, 180), "#160704")
    apple.paste(square(180), mask=square(180).getchannel("A"))
    apple.save(WEB / "app/apple-icon.png")
square(192).save(RES / "iqro_seal_notification_large.png")

# Android tints small icons. Keep the wax outline, lettering and flourish,
# leaving the red wax transparent so the mark does not become a solid disc.
seal = square(88)
mask = Image.new("L", seal.size)
mask.putdata([
    a if g > 75 and g > r * 0.48 and g > b * 1.35 else 0
    for r, g, b, a in seal.getdata()
])
silhouette = seal.getchannel("A").point(lambda alpha: 255 if alpha >= 128 else 0)
outline = ImageChops.subtract(silhouette, silhouette.filter(ImageFilter.MinFilter(5)))
mask = ImageChops.lighter(mask, outline)
mark = Image.new("RGBA", seal.size, "white")
mark.putalpha(mask)
badge = Image.new("RGBA", (96, 96))
badge.alpha_composite(mark, ((96 - mark.width) // 2, (96 - mark.height) // 2))
badge.save(RES / "iqro_seal_notification.png")
# A new resource ID also makes SystemUI reload icons cached before an APK update.
badge.save(RES / "iqro_status_icon.png")
# Saved Android alarms may still refer to the previous resource names.
badge.save(RES / "ic_notification_iqro.png")
square(192).save(RES / "iqro_notification_logo.png")
if not args.mobile_only:
    badge.save(WEB / "public/iqro-notification-badge.png")

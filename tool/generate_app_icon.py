"""Draws the Jotswift app icon and writes every size for iOS, Android and web.

Run from the repo root:  python3 tool/generate_app_icon.py
Needs Pillow (pip install pillow).
"""

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# Classic skin colors.
NAVY = (44, 74, 124)
NAVY_DARK = (31, 52, 92)
PAPER = (255, 255, 255)
RULE = (201, 214, 234)
MARGIN = (232, 160, 160)
INK = (200, 85, 61)

SS = 2048  # supersampled canvas; scaled down for every output


def draw_page(w, h):
    """The notebook page, upright, with ruling and the ink stroke."""
    page = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(page)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=int(w * 0.06), fill=PAPER)

    line_w = max(2, int(w * 0.012))
    gap = h / 7.2
    for i in range(1, 7):
        y = int(gap * i + gap * 0.35)
        d.line([(int(w * 0.05), y), (int(w * 0.95), y)], fill=RULE, width=line_w)
    mx = int(w * 0.2)
    d.line([(mx, 0), (mx, h)], fill=MARGIN, width=line_w)

    # Cursive loops (a prolate cycloid) rising from the fourth rule and
    # curling at the top, thicker mid-stroke like a pressure-sensitive pen.
    baseline = gap * 4 + gap * 0.35
    x0, x1 = w * 0.29, w * 0.8
    turns = 3
    t0, t1 = -1.2, 2 * math.pi * turns + 0.6
    a = (x1 - x0) / (t1 - t0)
    b, c = a * 2.8, gap * 1.35
    steps = 1600
    for i in range(steps + 1):
        t = t0 + (t1 - t0) * i / steps
        x = x0 + a * (t - t0) + b * (math.sin(t) - math.sin(t0))
        y = baseline - c * (1 - math.cos(t)) / 2
        p = i / steps
        r = w * (0.011 + 0.011 * math.sin(math.pi * p) ** 0.5)
        d.ellipse([x - r, y - r, x + r, y + r], fill=INK)
    return page


def render(size, content_scale=1.0, corner=0.0, alpha=True):
    canvas = Image.new("RGBA", (SS, SS), NAVY + (255,))

    # Soft diagonal shading on the background.
    shade = Image.new("L", (2, 2))
    shade.putdata([0, 70, 70, 140])
    shade = shade.resize((SS, SS), Image.BILINEAR)
    canvas = Image.composite(Image.new("RGBA", (SS, SS), NAVY_DARK + (255,)), canvas, shade)

    pw, ph = int(SS * 0.56 * content_scale), int(SS * 0.68 * content_scale)
    page = draw_page(pw, ph).rotate(-7, resample=Image.BICUBIC, expand=True)
    ox, oy = (SS - page.width) // 2, (SS - page.height) // 2 + int(SS * 0.01)

    shadow = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    shadow.paste((10, 20, 40, 120), (ox + int(SS * 0.015), oy + int(SS * 0.03)), page.split()[3])
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(SS * 0.025)))
    canvas.alpha_composite(page, (ox, oy))

    if corner:
        mask = Image.new("L", (SS, SS), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, SS - 1, SS - 1], radius=int(SS * corner), fill=255)
        canvas.putalpha(mask)

    out = canvas.resize((size, size), Image.LANCZOS)
    return out if alpha else out.convert("RGB")


def main():
    root = Path(__file__).resolve().parent.parent

    # iOS: full-bleed square, no transparency (the system rounds the corners).
    ios = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    master = render(1024, alpha=False)
    for img in json.loads((ios / "Contents.json").read_text())["images"]:
        if "filename" not in img:
            continue
        px = round(float(img["size"].split("x")[0]) * int(img["scale"][0]))
        master.resize((px, px), Image.LANCZOS).save(ios / img["filename"])

    # Android legacy launcher icons: rounded square.
    rounded = render(512, corner=0.2)
    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        rounded.resize((px, px), Image.LANCZOS).save(root / f"android/app/src/main/res/mipmap-{folder}/ic_launcher.png")

    # Web: rounded icons, plus maskable ones with the page inside the safe zone.
    web = root / "web"
    for px in (192, 512):
        rounded.resize((px, px), Image.LANCZOS).save(web / f"icons/Icon-{px}.png")
    maskable = render(512, content_scale=0.8)
    for px in (192, 512):
        maskable.resize((px, px), Image.LANCZOS).save(web / f"icons/Icon-maskable-{px}.png")
    rounded.resize((32, 32), Image.LANCZOS).save(web / "favicon.png")


if __name__ == "__main__":
    main()

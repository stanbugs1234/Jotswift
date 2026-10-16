"""Makes the Jotswift app icon in every size for iOS, Android and web.

The artwork is tool/app_icon_source.png: the icon as a rounded square on
white. Its rounded square is cut out and its gradient carried into the
corners, giving the full-bleed square iOS wants (iOS rounds it itself).

Run from the repo root:  python3 tool/generate_app_icon.py
Needs Pillow (pip install pillow).
"""

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "tool/app_icon_source.png"


def full_bleed():
    """The artwork as a square with no white corners, 1024 px."""
    art = Image.open(SOURCE).convert("RGB")
    r, _, b = art.split()
    # The rounded square is the blue part (and the white page inside it).
    blue = ImageChops.subtract(b, r).point(lambda v: 255 if v > 60 else 0)
    box = blue.getbbox()
    art = art.crop(box)
    w, h = art.size

    # The background is a smooth gradient: sample it on a 3x3 grid (where
    # an upscale puts its pixels), skipping the white page and wing.
    def at(fx, fy):
        patch = art.crop((int(w * fx) - 8, int(h * fy) - 8, int(w * fx) + 8, int(h * fy) + 8))
        color = patch.resize((1, 1), Image.BOX).getpixel((0, 0))
        return None if color[0] > 120 else color

    spots = (1 / 6, 1 / 2, 5 / 6)
    grid = [[at(x, y) for x in spots] for y in spots]
    for y in range(3):
        for x in range(3):
            if grid[y][x] is None:
                near = [
                    grid[y + dy][x + dx]
                    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1))
                    if 0 <= y + dy < 3 and 0 <= x + dx < 3 and grid[y + dy][x + dx]
                ]
                grid[y][x] = tuple(sum(c[i] for c in near) // len(near) for i in range(3))
    small = Image.new("RGB", (3, 3))
    small.putdata([c for row in grid for c in row])
    background = small.resize((w, h), Image.BILINEAR)

    # Keep the artwork in the middle, around the page and wing; the edge
    # (rounded corners and their rim) becomes the plain gradient.
    inset = int(w * 0.12)
    inside = Image.new("L", (w, h), 0)
    ImageDraw.Draw(inside).rounded_rectangle(
        [inset, inset, w - inset, h - inset], radius=int(w * 0.2), fill=255
    )
    inside = inside.filter(ImageFilter.GaussianBlur(w * 0.03))

    return Image.composite(art, background, inside).resize((1024, 1024), Image.LANCZOS)


def rounded(square, corner=0.2):
    out = square.convert("RGBA")
    mask = Image.new("L", out.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, out.width - 1, out.height - 1], radius=int(out.width * corner), fill=255
    )
    out.putalpha(mask)
    return out


def main():
    master = full_bleed()

    # iOS: full-bleed square, no transparency (the system rounds the corners).
    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for img in json.loads((ios / "Contents.json").read_text())["images"]:
        if "filename" not in img:
            continue
        px = round(float(img["size"].split("x")[0]) * int(img["scale"][0]))
        master.resize((px, px), Image.LANCZOS).save(ios / img["filename"])

    # Android legacy launcher icons: rounded square.
    corners = rounded(master)
    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        corners.resize((px, px), Image.LANCZOS).save(
            ROOT / f"android/app/src/main/res/mipmap-{folder}/ic_launcher.png"
        )

    # Web: rounded icons, and maskable ones (full bleed; the page and wing
    # sit inside the safe circle).
    web = ROOT / "web"
    for px in (192, 512):
        corners.resize((px, px), Image.LANCZOS).save(web / f"icons/Icon-{px}.png")
        master.resize((px, px), Image.LANCZOS).save(web / f"icons/Icon-maskable-{px}.png")
    corners.resize((32, 32), Image.LANCZOS).save(web / "favicon.png")


if __name__ == "__main__":
    main()

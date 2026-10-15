"""Makes Jotswift's cover packs, drawn in code with Pillow: Textures,
Patterns and Seasons, twelve covers each.

  python3 tool/make_covers.py all            # every pack
  python3 tool/make_covers.py covers_textures

Each pack is a collection (catalog/<pack>/: listing and preview) and its
covers are items in it (catalog/<pack>_<n>/: cover.webp 1536 x 2048,
preview.webp and listing.json), so buying the pack unlocks every cover.
Covers are random but seeded, so re-running draws the same images.
Re-running keeps each item's version; raise it by hand when images
change.
"""

import json
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
W, H = 1536, 2048


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def noise(sigma=40, scale=1, blur=0):
    """Grey noise around mid-grey, optionally coarser ([scale]) or soft."""
    n = Image.effect_noise((W // scale, H // scale), sigma)
    if scale > 1:
        n = n.resize((W, H), Image.BICUBIC)
    if blur:
        n = n.filter(ImageFilter.GaussianBlur(blur))
    return n


def tinted(base, n, amount):
    """[base] darkened and lightened by noise [n] (mid-grey = no change)."""
    im = Image.new("RGB", (W, H), base)
    light = Image.new("RGB", (W, H), mix(base, (255, 255, 255), amount))
    dark = Image.new("RGB", (W, H), mix(base, (0, 0, 0), amount))
    up = n.point(lambda v: max(0, v - 128) * 2)
    down = n.point(lambda v: max(0, 128 - v) * 2)
    im = Image.composite(light, im, up)
    return Image.composite(dark, im, down)


# Textures


def linen(c):
    im = tinted(c, noise(30), 0.06)
    d = ImageDraw.Draw(im)
    rnd = random.Random(1)
    for y in range(0, H, 4):
        d.line([(0, y), (W, y)], fill=mix(c, (255, 255, 255), rnd.uniform(0, 0.08)), width=1)
    for x in range(0, W, 4):
        d.line([(x, 0), (x, H)], fill=mix(c, (0, 0, 0), rnd.uniform(0, 0.06)), width=1)
    return im


def leather(c):
    n = noise(60, 2, 1.2)
    im = tinted(c, n, 0.12)
    im = tinted_vignette(im, 0.25)
    d = ImageDraw.Draw(im)
    for k in range(int(W * 0.04), int(W * 0.04) + 1):
        d.rectangle((60, 60, W - 60, H - 60), outline=mix(c, (255, 255, 255), 0.25), width=0)
    # Stitching.
    for x0, y0, x1, y1 in ((80, 80, W - 80, 80), (W - 80, 80, W - 80, H - 80), (80, H - 80, W - 80, H - 80), (80, 80, 80, H - 80)):
        length = math.hypot(x1 - x0, y1 - y0)
        for t in range(0, int(length), 36):
            a, b = t / length, min(1, (t + 20) / length)
            d.line([(x0 + (x1 - x0) * a, y0 + (y1 - y0) * a), (x0 + (x1 - x0) * b, y0 + (y1 - y0) * b)],
                   fill=mix(c, (255, 240, 220), 0.5), width=6)
    return im


def tinted_vignette(im, amount):
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).ellipse((-W * 0.3, -H * 0.2, W * 1.3, H * 1.2), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(220))
    dark = Image.blend(im, Image.new("RGB", (W, H), (0, 0, 0)), amount)
    return Image.composite(im, dark, mask)


def kraft(c):
    im = tinted(c, noise(50, 1, 0.6), 0.08)
    d = ImageDraw.Draw(im)
    rnd = random.Random(3)
    for _ in range(5000):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        r = rnd.uniform(1, 3.5)
        d.ellipse((x - r, y - r, x + r, y + r), fill=mix(c, (60, 40, 20), rnd.uniform(0.2, 0.5)))
    for _ in range(600):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        a, ln = rnd.uniform(0, math.pi), rnd.uniform(8, 30)
        d.line([(x, y), (x + ln * math.cos(a), y + ln * math.sin(a))], fill=mix(c, (255, 255, 255), 0.25), width=2)
    return im


def marble(c):
    im = tinted(c, noise(20, 4, 6), 0.05)
    d = ImageDraw.Draw(im)
    rnd = random.Random(4)
    vein = mix(c, (90, 90, 100) if sum(c) > 380 else (230, 230, 230), 0.55)
    for _ in range(14):
        x, y = rnd.uniform(-200, W), rnd.uniform(-200, H * 0.3)
        a = rnd.uniform(0.6, 1.2)
        pts = []
        for _ in range(140):
            pts.append((x, y))
            a += rnd.uniform(-0.25, 0.25)
            x, y = x + 18 * math.cos(a), y + 18 * math.sin(a)
        d.line(pts, fill=vein, width=rnd.choice((2, 3, 5)), joint="curve")
    return im.filter(ImageFilter.GaussianBlur(1.4))


def cork(c):
    im = tinted(c, noise(70, 3, 1), 0.18)
    d = ImageDraw.Draw(im)
    rnd = random.Random(5)
    for _ in range(9000):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        r = rnd.uniform(2, 7)
        d.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), fill=mix(c, (70, 40, 20), rnd.uniform(0.1, 0.45)))
    return im


def denim(c):
    im = tinted(c, noise(40), 0.1)
    d = ImageDraw.Draw(im)
    for k in range(-H, W, 7):
        d.line([(k, 0), (k + H * 0.6, H)], fill=mix(c, (255, 255, 255), 0.12), width=2)
    im = tinted_vignette(im, 0.2)
    d = ImageDraw.Draw(im)
    for x in (W - 220, W - 196):
        for y in range(0, H, 34):
            d.line([(x, y), (x, y + 20)], fill=(222, 164, 80), width=6)
    return im


def velvet(c):
    im = Image.new("RGB", (W, H), c)
    shine = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shine).ellipse((-W * 0.4, H * 0.05, W * 0.9, H * 0.7), fill=180)
    shine = shine.filter(ImageFilter.GaussianBlur(300))
    im = Image.composite(Image.new("RGB", (W, H), mix(c, (255, 255, 255), 0.25)), im, shine)
    return tinted(im.getpixel((W // 2, H // 2)), noise(25), 0.03) if False else Image.blend(im, tinted(c, noise(25), 0.05), 0.3)


def terrazzo(c):
    im = tinted(c, noise(15), 0.03)
    d = ImageDraw.Draw(im)
    rnd = random.Random(8)
    chips = [rgb("#E07A5F"), rgb("#3D405B"), rgb("#81B29A"), rgb("#F2CC8F"), rgb("#B5838D"), (250, 250, 250)]
    for _ in range(700):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        r = rnd.choice((6, 9, 14, 22, 34))
        pts = [(x + r * rnd.uniform(0.6, 1.2) * math.cos(a), y + r * rnd.uniform(0.6, 1.2) * math.sin(a))
               for a in [k * 2 * math.pi / 6 + rnd.uniform(-0.3, 0.3) for k in range(6)]]
        d.polygon(pts, fill=rnd.choice(chips))
    return im


def watercolor(c):
    im = Image.new("RGB", (W, H), (252, 250, 246))
    rnd = random.Random(9)
    for k in range(9):
        layer = Image.new("L", (W, H), 0)
        ld = ImageDraw.Draw(layer)
        x, y, r = rnd.uniform(0, W), rnd.uniform(0, H), rnd.uniform(300, 700)
        ld.ellipse((x - r, y - r * 0.8, x + r, y + r * 0.8), fill=int(rnd.uniform(70, 150)))
        layer = layer.filter(ImageFilter.GaussianBlur(120))
        col = mix(c, rnd.choice([(255, 255, 255), (255, 200, 200), (200, 220, 255)]), rnd.uniform(0, 0.4))
        im = Image.composite(Image.new("RGB", (W, H), col), im, layer)
    return Image.blend(im, tinted(mix(c, (255, 255, 255), 0.6), noise(30, 2, 2), 0.05), 0.15)


def concrete(c):
    im = tinted(c, noise(45, 6, 3), 0.1)
    im = Image.blend(im, tinted(c, noise(35), 0.06), 0.5)
    d = ImageDraw.Draw(im)
    rnd = random.Random(10)
    for _ in range(400):
        x, y, r = rnd.uniform(0, W), rnd.uniform(0, H), rnd.uniform(1, 4)
        d.ellipse((x - r, y - r, x + r, y + r), fill=mix(c, (40, 40, 40), 0.35))
    return im


def wood(c):
    im = Image.new("RGB", (W, H), c)
    d = ImageDraw.Draw(im)
    rnd = random.Random(11)
    x = 0
    while x < W:
        wobble = rnd.uniform(10, 40)
        phase = rnd.uniform(0, 6)
        col = mix(c, (60, 30, 10), rnd.uniform(0.05, 0.3))
        pts = [(x + wobble * math.sin(y / 260 + phase), y) for y in range(0, H + 20, 20)]
        d.line(pts, fill=col, width=rnd.choice((2, 3, 4, 6)))
        x += rnd.uniform(10, 34)
    return Image.blend(im.filter(ImageFilter.GaussianBlur(1.5)), tinted(c, noise(30), 0.05), 0.25)


def felt(c):
    return tinted(c, noise(60, 1, 1.6), 0.14)


TEXTURES = [
    ("Linen", linen, "#D9CFC1"), ("Leather", leather, "#7A4A30"), ("Kraft", kraft, "#C09A6B"),
    ("Marble", marble, "#EEEAE6"), ("Cork", cork, "#C8955E"), ("Denim", denim, "#3D5A80"),
    ("Velvet", velvet, "#5B2A4A"), ("Terrazzo", terrazzo, "#F1ECE4"), ("Watercolour", watercolor, "#8FB8DE"),
    ("Concrete", concrete, "#A7A9AC"), ("Wood", wood, "#B07A4A"), ("Felt", felt, "#4F7A5A"),
]


# Patterns


def stripes(a, b):
    im = Image.new("RGB", (W, H), a)
    d = ImageDraw.Draw(im)
    for x in range(0, W, 160):
        d.rectangle((x, 0, x + 70, H), fill=b)
    return im


def polka(a, b):
    im = Image.new("RGB", (W, H), a)
    d = ImageDraw.Draw(im)
    for r, y in enumerate(range(0, H + 120, 120)):
        for x in range(0 + (60 if r % 2 else 0), W + 120, 120):
            d.ellipse((x - 22, y - 22, x + 22, y + 22), fill=b)
    return im


def gingham(a, b):
    im = Image.new("RGB", (W, H), a)
    over = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    for x in range(0, W, 128):
        d.rectangle((x, 0, x + 64, H), fill=b + (120,))
    for y in range(0, H, 128):
        d.rectangle((0, y, W, y + 64), fill=b + (120,))
    im.paste(over, (0, 0), over)
    return im


def checker(a, b):
    im = Image.new("RGB", (W, H), a)
    d = ImageDraw.Draw(im)
    s = 192
    for y in range(0, H, s):
        for x in range(0, W, s):
            if (x // s + y // s) % 2:
                d.rectangle((x, y, x + s, y + s), fill=b)
    return im


def chevron(a, b):
    im = Image.new("RGB", (W, H), a)
    d = ImageDraw.Draw(im)
    for y in range(-200, H + 200, 200):
        pts = [(x, y + (0 if (x // 160) % 2 == 0 else 120)) for x in range(-160, W + 320, 160)]
        pts = [(x, y + (120 if i % 2 else 0)) for i, (x, _) in enumerate(pts)]
        d.line(pts, fill=b, width=56, joint="curve")
    return im


def herringbone(a, b):
    im = Image.new("RGB", (W, H), a)
    d = ImageDraw.Draw(im)
    s = 90
    for col in range(0, W // s + 2):
        for row in range(-2, H // s + 3):
            x, y = col * s, row * s
            if col % 2:
                d.polygon([(x, y), (x + s, y + s), (x + s, y + s + 26), (x, y + 26)], fill=b)
            else:
                d.polygon([(x, y + s), (x + s, y), (x + s, y + 26), (x, y + s + 26)], fill=b)
    return im


def grid(a, b):
    im = Image.new("RGB", (W, H), a)
    d = ImageDraw.Draw(im)
    for x in range(0, W, 96):
        d.line([(x, 0), (x, H)], fill=b, width=4)
    for y in range(0, H, 96):
        d.line([(0, y), (W, y)], fill=b, width=4)
    return im


def waves(a, b):
    im = Image.new("RGB", (W, H), a)
    d = ImageDraw.Draw(im)
    for y in range(0, H + 100, 100):
        pts = [(x, y + 26 * math.sin(x / 70)) for x in range(0, W + 10, 10)]
        d.line(pts, fill=b, width=14, joint="curve")
    return im


def triangles(a, b):
    im = Image.new("RGB", (W, H), a)
    d = ImageDraw.Draw(im)
    rnd = random.Random(21)
    s = 192
    h = s * math.sqrt(3) / 2
    for r in range(int(H / h) + 2):
        for k in range(-1, W // s + 2):
            x = k * s + (s / 2 if r % 2 else 0)
            y = r * h
            col = mix(b, a, rnd.choice((0, 0.3, 0.6, 1)))
            d.polygon([(x, y), (x + s, y), (x + s / 2, y + h)], fill=col)
    return im


def scallops(a, b):
    im = Image.new("RGB", (W, H), a)
    d = ImageDraw.Draw(im)
    s = 128
    for r, y in enumerate(range(-s, H + s, s // 2)):
        for x in range(-s, W + s, s):
            x0 = x + (s // 2 if r % 2 else 0)
            d.ellipse((x0, y, x0 + s, y + s), fill=b if r % 2 else a, outline=mix(a, b, 0.5), width=6)
    return im


def plaid(a, b):
    im = Image.new("RGB", (W, H), a)
    over = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    for x in range(0, W, 300):
        d.rectangle((x, 0, x + 120, H), fill=b + (110,))
        d.rectangle((x + 170, 0, x + 186, H), fill=(255, 255, 255, 90))
    for y in range(0, H, 300):
        d.rectangle((0, y, W, y + 120), fill=b + (110,))
        d.rectangle((0, y + 170, W, y + 186), fill=(255, 255, 255, 90))
    im.paste(over, (0, 0), over)
    return im


def confetti(a, b):
    im = Image.new("RGB", (W, H), a)
    d = ImageDraw.Draw(im)
    rnd = random.Random(22)
    cols = [b, rgb("#F2CC8F"), rgb("#81B29A"), rgb("#E07A5F"), rgb("#9FB7E8")]
    for _ in range(420):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H)
        a_ = rnd.uniform(0, math.pi)
        ln = rnd.uniform(20, 46)
        d.line([(x, y), (x + ln * math.cos(a_), y + ln * math.sin(a_))], fill=rnd.choice(cols), width=12)
    return im


PATTERNS = [
    ("Stripes", stripes, "#F7E7D7", "#E9A38A"), ("Polka dots", polka, "#2E4057", "#F2E8CF"),
    ("Gingham", gingham, "#FFFFFF", "#D96C75"), ("Checks", checker, "#F4EBDD", "#C7B299"),
    ("Chevron", chevron, "#E8F1F2", "#5B8C9A"), ("Herringbone", herringbone, "#3F3F46", "#6B6B75"),
    ("Grid", grid, "#FAF7F0", "#A9C2D6"), ("Waves", waves, "#D9ECF2", "#4A90B8"),
    ("Triangles", triangles, "#F5F1EB", "#2F5D62"), ("Scallops", scallops, "#F8E1E7", "#E8A8BA"),
    ("Plaid", plaid, "#2C4A3B", "#A23B3B"), ("Confetti", confetti, "#FFFDF8", "#B39DDB"),
]


# Seasons


def scatter(base, draw_one, count, seed, size=(70, 140)):
    im = Image.new("RGB", (W, H), base)
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    step = int(math.sqrt(W * H / count))
    for r, y in enumerate(range(0, H + step, step)):
        for x in range(0 + (step // 2 if r % 2 else 0), W + step, step):
            draw_one(d, x + rnd.uniform(-step * 0.25, step * 0.25), y + rnd.uniform(-step * 0.25, step * 0.25),
                     rnd.uniform(*size), rnd)
    return im


def blossom(d, x, y, s, rnd):
    col = rnd.choice([rgb("#F4B6C2"), rgb("#F9D5DC"), rgb("#FFFFFF")])
    for k in range(5):
        a = k * 2 * math.pi / 5
        d.ellipse((x + s * 0.45 * math.cos(a) - s * 0.3, y + s * 0.45 * math.sin(a) - s * 0.3,
                   x + s * 0.45 * math.cos(a) + s * 0.3, y + s * 0.45 * math.sin(a) + s * 0.3), fill=col)
    d.ellipse((x - s * 0.15, y - s * 0.15, x + s * 0.15, y + s * 0.15), fill=rgb("#F2C14E"))


def citrus(d, x, y, s, rnd):
    col = rnd.choice([rgb("#F6C445"), rgb("#F28C38"), rgb("#9BC53D")])
    d.ellipse((x - s / 2, y - s / 2, x + s / 2, y + s / 2), fill=col)
    d.ellipse((x - s * 0.42, y - s * 0.42, x + s * 0.42, y + s * 0.42), fill=mix(col, (255, 255, 255), 0.55))
    for k in range(8):
        a = k * math.pi / 4
        d.line([(x, y), (x + s * 0.4 * math.cos(a), y + s * 0.4 * math.sin(a))], fill=col, width=4)


def autumn_leaf(d, x, y, s, rnd):
    col = rnd.choice([rgb("#C8553D"), rgb("#F28F3B"), rgb("#E9B44C"), rgb("#8C5E34")])
    a = rnd.uniform(0, 2 * math.pi)
    pts = []
    for i in range(30):
        t = i / 30 * 2 * math.pi
        px, py = s / 2 * math.cos(t), s / 4 * math.sin(t) * (1 - 0.3 * math.cos(t))
        pts.append((x + px * math.cos(a) - py * math.sin(a), y + px * math.sin(a) + py * math.cos(a)))
    d.polygon(pts, fill=col)


def snowflake(d, x, y, s, rnd):
    col = (255, 255, 255)
    for k in range(6):
        a = k * math.pi / 3
        d.line([(x, y), (x + s / 2 * math.cos(a), y + s / 2 * math.sin(a))], fill=col, width=5)
        bx, by = x + s * 0.3 * math.cos(a), y + s * 0.3 * math.sin(a)
        for sgn in (-1, 1):
            a2 = a + sgn * 0.7
            d.line([(bx, by), (bx + s * 0.14 * math.cos(a2), by + s * 0.14 * math.sin(a2))], fill=col, width=4)


def ornament(d, x, y, s, rnd):
    col = rnd.choice([rgb("#C0392B"), rgb("#F1C40F"), rgb("#27AE60"), rgb("#ECF0F1")])
    d.line([(x, y - s), (x, y - s / 2)], fill=rgb("#D4AF37"), width=4)
    d.ellipse((x - s / 2, y - s / 2, x + s / 2, y + s / 2), fill=col)
    d.ellipse((x - s * 0.25, y - s * 0.3, x - s * 0.08, y - s * 0.13), fill=mix(col, (255, 255, 255), 0.6))


def heart(d, x, y, s, rnd):
    col = rnd.choice([rgb("#E63946"), rgb("#F4A3B4"), rgb("#FFFFFF")])
    pts = []
    for i in range(40):
        t = i / 40 * 2 * math.pi
        hx = 16 * math.sin(t) ** 3
        hy = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x + hx * s / 34, y - hy * s / 34))
    d.polygon(pts, fill=col)


def spooky(d, x, y, s, rnd):
    if rnd.random() < 0.5:
        col = rgb("#F28C28")
        for dx in (-s * 0.25, s * 0.25, 0):
            d.ellipse((x + dx - s * 0.35, y - s * 0.32, x + dx + s * 0.35, y + s * 0.32), fill=col)
        d.rectangle((x - 4, y - s * 0.5, x + 4, y - s * 0.3), fill=rgb("#4C7A3A"))
    else:
        r = s * 0.12
        d.ellipse((x - r, y - r, x + r, y + r), fill=rgb("#F7E7A1"))


def egg(d, x, y, s, rnd):
    col = rnd.choice([rgb("#BDE0FE"), rgb("#FFC8DD"), rgb("#CDB4DB"), rgb("#FFF1A8"), rgb("#B9E4C9")])
    d.ellipse((x - s * 0.35, y - s / 2, x + s * 0.35, y + s / 2), fill=col)
    d.line([(x - s * 0.33, y), (x + s * 0.33, y)], fill=(255, 255, 255), width=6)


def shell(d, x, y, s, rnd):
    col = rnd.choice([rgb("#F6D6AD"), rgb("#F4B183"), rgb("#FFFFFF")])
    d.pieslice((x - s / 2, y - s / 2, x + s / 2, y + s / 2), 180, 360, fill=col)
    for k in range(5):
        a = math.pi + k * math.pi / 4
        d.line([(x, y), (x + s / 2 * math.cos(a), y + s / 2 * math.sin(a))], fill=mix(col, (150, 100, 70), 0.3), width=3)


def star(d, x, y, s, rnd):
    col = rnd.choice([rgb("#F7E7A1"), (255, 255, 255), rgb("#D4AF37")])
    r = s * rnd.uniform(0.15, 0.4)
    pts = [(x + (r if i % 2 == 0 else r * 0.4) * math.cos(-math.pi / 2 + i * math.pi / 5),
            y + (r if i % 2 == 0 else r * 0.4) * math.sin(-math.pi / 2 + i * math.pi / 5)) for i in range(10)]
    d.polygon(pts, fill=col)


def gold_confetti(d, x, y, s, rnd):
    col = rnd.choice([rgb("#D4AF37"), rgb("#F5E6A8"), (255, 255, 255)])
    r = s * 0.1
    if rnd.random() < 0.5:
        d.ellipse((x - r, y - r, x + r, y + r), fill=col)
    else:
        d.rectangle((x - r, y - r * 0.5, x + r, y + r * 0.5), fill=col)


def festive_plaid():
    return plaid(rgb("#8E1B1B"), rgb("#1E4D2B"))


def beach():
    im = Image.new("RGB", (W, H), rgb("#F3E3C3"))
    d = ImageDraw.Draw(im)
    for k, col in enumerate(("#9ED8DB", "#5CB8C4", "#2F8FA3", "#1F6F8B")):
        y0 = H * (0.1 + k * 0.12)
        pts = [(x, y0 + 30 * math.sin(x / 120 + k)) for x in range(0, W + 20, 20)] + [(W, H), (0, H)]
        d.polygon(pts, fill=rgb(col))
    sand = Image.new("RGB", (W, H), rgb("#F3E3C3"))
    mask = Image.new("L", (W, H), 0)
    pts = [(x, H * 0.62 + 40 * math.sin(x / 200)) for x in range(0, W + 20, 20)] + [(W, H), (0, H)]
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    im = Image.composite(sand, im, mask)
    rnd = random.Random(31)
    d = ImageDraw.Draw(im)
    for _ in range(14):
        shell(d, rnd.uniform(80, W - 80), rnd.uniform(H * 0.7, H - 80), rnd.uniform(60, 110), rnd)
    return im


SEASONS = [
    ("Spring blossom", lambda: scatter(rgb("#DDEFE0"), blossom, 60, 41), "#DDEFE0"),
    ("Summer citrus", lambda: scatter(rgb("#FFF6DD"), citrus, 50, 42), "#FFF6DD"),
    ("Beach day", beach, "#9ED8DB"),
    ("Autumn leaves", lambda: scatter(rgb("#F6E7D2"), autumn_leaf, 90, 43, (80, 150)), "#F6E7D2"),
    ("Pumpkin night", lambda: scatter(rgb("#2B2340"), spooky, 70, 44, (90, 150)), "#2B2340"),
    ("First snow", lambda: scatter(rgb("#7FA7C9"), snowflake, 70, 45), "#7FA7C9"),
    ("Ornaments", lambda: scatter(rgb("#1E4D2B"), ornament, 50, 46, (60, 100)), "#1E4D2B"),
    ("Festive plaid", festive_plaid, "#8E1B1B"),
    ("Sweethearts", lambda: scatter(rgb("#F9D5DC"), heart, 70, 47), "#F9D5DC"),
    ("Pastel eggs", lambda: scatter(rgb("#FFFDF5"), egg, 60, 48, (80, 130)), "#FFFDF5"),
    ("Starry night", lambda: scatter(rgb("#14213D"), star, 160, 49), "#14213D"),
    ("New year", lambda: scatter(rgb("#1B1B1F"), gold_confetti, 260, 50), "#1B1B1F"),
]


def textures():
    return [(name, lambda f=f, c=c: f(rgb(c)), c) for name, f, c in TEXTURES]


def patterns():
    return [(name, lambda f=f, a=a, b=b: f(rgb(a), rgb(b)), a) for name, f, a, b in PATTERNS]


def seasons():
    return list(SEASONS)


PACKS = {
    "covers_textures": ("Texture Covers", textures, ["covers", "textures", "leather", "linen", "marble"]),
    "covers_patterns": ("Pattern Covers", patterns, ["covers", "patterns", "stripes", "plaid"]),
    "covers_seasonal": ("Seasonal Covers", seasons, ["covers", "seasons", "holidays"]),
}


def write_listing(folder, listing):
    path = folder / "listing.json"
    if path.exists():
        listing["version"] = json.loads(path.read_text()).get("version", 1)
    path.write_text(json.dumps(listing, indent=2) + "\n")


def write(pid):
    title, make, tags = PACKS[pid]
    previews = []
    for i, (name, draw, color) in enumerate(make(), start=1):
        folder = ROOT / "catalog" / f"{pid}_{i}"
        folder.mkdir(parents=True, exist_ok=True)
        im = draw()
        im.save(folder / "cover.webp", "WEBP", quality=86)
        prev = im.resize((384, 512), Image.LANCZOS)
        prev.save(folder / "preview.webp", "WEBP", quality=86)
        previews.append(prev)
        write_listing(folder, {
            "kind": "cover", "name": name, "version": 1, "unlock": {}, "collectionId": pid,
            "category": "covers", "color": color if color.startswith("#") else "#888888", "tags": tags,
        })
    folder = ROOT / "catalog" / pid
    folder.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGB", (512, 384), (240, 238, 234))
    for k, prev in enumerate(previews[:8]):
        t = prev.resize((112, 150), Image.LANCZOS)
        sheet.paste(t, (16 + (k % 4) * 124, 26 + (k // 4) * 170))
    sheet.save(folder / "preview.webp", "WEBP", quality=88)
    write_listing(folder, {
        "kind": "collection", "name": title, "version": 1,
        "unlock": {"pro": True, "products": [f"pack_{pid}"]}, "tags": tags,
    })
    return len(previews)


def main():
    args = sys.argv[1:]
    if len(args) != 1 or (args[0] != "all" and args[0] not in PACKS):
        sys.exit(__doc__)
    for pid in PACKS if args[0] == "all" else args:
        print(f"{pid}: {write(pid)} covers")


if __name__ == "__main__":
    main()

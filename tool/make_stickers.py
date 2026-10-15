"""Makes Jotswift's sticker packs, drawn in code with Pillow.

  python3 tool/make_stickers.py all          # every pack
  python3 tool/make_stickers.py stickers_emoji

Each pack becomes catalog/<id>/ with stickers/*.webp (transparent, 512 px,
or wider for tape and labels), stickers.json, preview.webp and
listing.json. Stickers are drawn at twice their size and scaled down, so
edges are smooth. Re-running keeps each item's version; raise it by hand
when the images change.
"""

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SIZE = 512
K = 2  # drawn at K x SIZE, then scaled down

INK = (52, 48, 62)
PALETTE = {
    "coral": (240, 128, 112), "peach": (247, 183, 140), "sun": (246, 200, 92), "mint": (128, 202, 168),
    "sky": (120, 180, 230), "lilac": (178, 150, 222), "rose": (236, 140, 176), "sage": (150, 180, 140),
    "navy": (52, 74, 124), "sand": (226, 204, 168), "white": (255, 255, 255), "grey": (170, 172, 180),
    "red": (222, 84, 84), "green": (92, 160, 104), "orange": (238, 146, 64), "brown": (150, 104, 72),
}
C = PALETTE


def font(size, bold=True):
    for n in ("/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
              "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
              "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(n, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


def canvas(w=SIZE, h=SIZE):
    im = Image.new("RGBA", (w * K, h * K), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def finish(im):
    return im.resize((im.width // K, im.height // K), Image.LANCZOS)


def lw(n):
    return int(n * K)


def P(x, y):
    """A point in 0-512 sticker units, scaled to the canvas."""
    return (x * K, y * K)


def box(x0, y0, x1, y1):
    return (x0 * K, y0 * K, x1 * K, y1 * K)


def badge(d, fill, outline=True):
    """A round badge behind an icon, with a white sticker edge."""
    d.ellipse(box(16, 16, 496, 496), fill=C["white"])
    d.ellipse(box(36, 36, 476, 476), fill=fill)


def star_pts(cx, cy, r, inner=0.45, n=5, rot=-math.pi / 2):
    return [P(cx + (r if i % 2 == 0 else r * inner) * math.cos(rot + i * math.pi / n),
              cy + (r if i % 2 == 0 else r * inner) * math.sin(rot + i * math.pi / n)) for i in range(2 * n)]


def heart_pts(cx, cy, r):
    pts = []
    for i in range(80):
        t = i / 80 * 2 * math.pi
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append(P(cx + x * r / 17, cy - y * r / 17))
    return pts


# Icons, drawn on a 512 square around (256, 256).

def icon_calendar(d, c):
    d.rounded_rectangle(box(136, 156, 376, 376), radius=24 * K, fill=C["white"], outline=INK, width=lw(10))
    d.rectangle(box(141, 161, 371, 216), fill=c)
    for x in (186, 326):
        d.rounded_rectangle(box(x - 9, 130, x + 9, 186), radius=8 * K, fill=INK)
    for r in range(3):
        for col in range(4):
            d.rounded_rectangle(box(166 + col * 48, 236 + r * 44, 196 + col * 48, 262 + r * 44), radius=5 * K,
                                fill=c if (r, col) == (1, 2) else (226, 228, 234))


def icon_clock(d, c):
    d.ellipse(box(136, 136, 376, 376), fill=C["white"], outline=INK, width=lw(10))
    for i in range(12):
        a = i * math.pi / 6
        d.line([P(256 + 96 * math.cos(a), 256 + 96 * math.sin(a)), P(256 + 108 * math.cos(a), 256 + 108 * math.sin(a))],
               fill=INK, width=lw(6))
    d.line([P(256, 256), P(256, 176)], fill=INK, width=lw(12))
    d.line([P(256, 256), P(316, 286)], fill=c, width=lw(12))
    d.ellipse(box(244, 244, 268, 268), fill=INK)


def icon_bell(d, c):
    d.pieslice(box(156, 140, 356, 340), 180, 360, fill=C["sun"])
    d.rectangle(box(156, 238, 356, 330), fill=C["sun"])
    d.rounded_rectangle(box(136, 320, 376, 350), radius=12 * K, fill=C["sun"], outline=INK, width=lw(8))
    d.arc(box(156, 140, 356, 340), 180, 360, fill=INK, width=lw(8))
    d.line([P(156, 240), P(156, 322)], fill=INK, width=lw(8))
    d.line([P(356, 240), P(356, 322)], fill=INK, width=lw(8))
    d.ellipse(box(232, 346, 280, 394), fill=INK)
    d.ellipse(box(244, 112, 268, 136), fill=INK)


def icon_heart(d, c):
    d.polygon(heart_pts(256, 266, 140), fill=C["red"])
    d.ellipse(box(196, 196, 226, 226), fill=(255, 210, 210))


def icon_star(d, c):
    d.polygon(star_pts(256, 266, 150), fill=C["sun"], outline=INK)


def icon_house(d, c):
    d.polygon([P(256, 136), P(386, 246), P(126, 246)], fill=C["coral"])
    d.rectangle(box(156, 240, 356, 380), fill=C["white"], outline=INK, width=lw(9))
    d.rectangle(box(226, 290, 286, 380), fill=C["brown"])
    d.line([P(116, 252), P(256, 132), P(396, 252)], fill=INK, width=lw(12), joint="curve")


def icon_car(d, c):
    d.rounded_rectangle(box(116, 250, 396, 340), radius=30 * K, fill=C["coral"], outline=INK, width=lw(8))
    d.polygon([P(166, 256), P(206, 186), P(316, 186), P(356, 256)], fill=C["coral"], outline=INK)
    d.polygon([P(186, 250), P(214, 202), P(250, 202), P(250, 250)], fill=C["sky"])
    d.polygon([P(266, 250), P(266, 202), P(306, 202), P(334, 250)], fill=C["sky"])
    for x in (176, 336):
        d.ellipse(box(x - 32, 310, x + 32, 374), fill=INK)
        d.ellipse(box(x - 14, 328, x + 14, 356), fill=C["grey"])


def icon_plane(d, c):
    d.rounded_rectangle(box(126, 236, 396, 276), radius=20 * K, fill=C["white"], outline=INK, width=lw(8))
    d.polygon([P(236, 246), P(196, 146), P(236, 146), P(306, 246)], fill=C["sky"], outline=INK)
    d.polygon([P(236, 266), P(196, 366), P(236, 366), P(306, 266)], fill=C["sky"], outline=INK)
    d.polygon([P(130, 246), P(116, 196), P(146, 196), P(170, 246)], fill=C["sky"], outline=INK)


def icon_book(d, c):
    d.polygon([P(256, 176), P(136, 150), P(136, 356), P(256, 382)], fill=C["white"], outline=INK)
    d.polygon([P(256, 176), P(376, 150), P(376, 356), P(256, 382)], fill=c, outline=INK)
    d.line([P(256, 176), P(256, 382)], fill=INK, width=lw(8))
    for k in range(4):
        d.line([P(160, 200 + k * 34), P(236, 216 + k * 34)], fill=(200, 202, 210), width=lw(6))


def icon_pencil(d, c):
    pts = [(180, 380), (156, 356), (316, 196), (340, 220)]
    d.polygon([P(*p) for p in pts], fill=C["sun"], outline=INK)
    d.polygon([P(316, 196), P(340, 220), P(368, 192), P(344, 168)], fill=C["rose"], outline=INK)
    d.polygon([P(156, 356), P(180, 380), P(136, 400)], fill=C["sand"], outline=INK)
    d.polygon([P(140, 388), P(148, 396), P(136, 400)], fill=INK)


def icon_cake(d, c):
    d.rounded_rectangle(box(146, 256, 366, 376), radius=16 * K, fill=C["peach"], outline=INK, width=lw(8))
    d.rectangle(box(150, 256, 362, 290), fill=C["white"])
    for k in range(6):
        x = 160 + k * 38
        d.ellipse(box(x - 4, 280, x + 26, 304), fill=C["white"])
    d.rectangle(box(244, 186, 268, 256), fill=c, outline=INK, width=lw(6))
    d.ellipse(box(240, 136, 272, 182), fill=C["sun"])


def icon_gift(d, c):
    d.rectangle(box(156, 236, 356, 376), fill=c, outline=INK, width=lw(8))
    d.rectangle(box(136, 196, 376, 246), fill=c, outline=INK, width=lw(8))
    d.rectangle(box(240, 196, 272, 376), fill=C["sun"])
    d.ellipse(box(186, 150, 256, 200), outline=C["sun"], width=lw(14))
    d.ellipse(box(256, 150, 326, 200), outline=C["sun"], width=lw(14))


def icon_coffee(d, c):
    d.rounded_rectangle(box(156, 200, 336, 376), radius=26 * K, fill=C["white"], outline=INK, width=lw(9))
    d.arc(box(306, 236, 386, 316), 270, 90, fill=INK, width=lw(12))
    d.rectangle(box(166, 210, 326, 236), fill=C["brown"])
    for x in (206, 246, 286):
        d.arc(box(x - 16, 120, x + 16, 190), 100, 260, fill=C["grey"], width=lw(7))


def icon_pill(d, c):
    im = Image.new("RGBA", d.im.size, (0, 0, 0, 0))
    dd = ImageDraw.Draw(im)
    dd.rounded_rectangle(box(116, 196, 396, 316), radius=60 * K, fill=C["white"], outline=INK, width=lw(10))
    dd.pieslice(box(121, 201, 231, 311), 90, 270, fill=C["sun"])
    dd.rectangle(box(176, 201, 256, 311), fill=C["sun"])
    dd.rounded_rectangle(box(116, 196, 396, 316), radius=60 * K, outline=INK, width=lw(10))
    dd.line([P(256, 200), P(256, 312)], fill=INK, width=lw(8))
    return im.rotate(-35, center=P(256, 256))


def icon_dollar(d, c):
    d.ellipse(box(146, 146, 366, 366), fill=C["sun"], outline=INK, width=lw(9))
    d.ellipse(box(170, 170, 342, 342), outline=(230, 170, 50), width=lw(6))
    f = font(150 * K)
    d.text(P(256, 262), "$", font=f, fill=INK, anchor="mm")


def icon_music(d, c):
    d.line([P(216, 350), P(216, 170)], fill=INK, width=lw(14))
    d.line([P(336, 320), P(336, 140)], fill=INK, width=lw(14))
    d.polygon([P(209, 166), P(343, 136), P(343, 180), P(209, 210)], fill=INK)
    d.ellipse(box(160, 320, 222, 372), fill=c)
    d.ellipse(box(280, 290, 342, 342), fill=c)


def icon_camera(d, c):
    d.rounded_rectangle(box(126, 196, 386, 366), radius=28 * K, fill=C["grey"], outline=INK, width=lw(9))
    d.rounded_rectangle(box(196, 166, 296, 206), radius=10 * K, fill=C["grey"], outline=INK, width=lw(8))
    d.ellipse(box(196, 222, 316, 342), fill=C["white"], outline=INK, width=lw(9))
    d.ellipse(box(226, 252, 286, 312), fill=c)


def icon_check(d, c):
    d.line([P(166, 266), P(226, 326), P(346, 196)], fill=C["white"], width=lw(40), joint="curve")


def icon_flag(d, c):
    d.line([P(176, 136), P(176, 386)], fill=INK, width=lw(12))
    d.polygon([P(182, 146), P(356, 146), P(316, 206), P(356, 266), P(182, 266)], fill=c, outline=INK)


def icon_bulb(d, c):
    d.ellipse(box(176, 130, 336, 290), fill=C["sun"], outline=INK, width=lw(9))
    d.rectangle(box(216, 270, 296, 300), fill=C["sun"])
    d.rounded_rectangle(box(214, 296, 298, 356), radius=10 * K, fill=C["grey"], outline=INK, width=lw(8))
    d.line([P(220, 316), P(292, 316)], fill=INK, width=lw(5))
    d.line([P(220, 334), P(292, 334)], fill=INK, width=lw(5))
    d.arc(box(216, 170, 296, 250), 200, 270, fill=C["white"], width=lw(8))


def icon_dumbbell(d, c):
    d.rounded_rectangle(box(176, 244, 336, 268), radius=8 * K, fill=C["grey"])
    for x in (136, 336):
        d.rounded_rectangle(box(x, 196, x + 40, 316), radius=10 * K, fill=c, outline=INK, width=lw(8))
    for x in (116, 376):
        d.rounded_rectangle(box(x, 222, x + 22, 290), radius=8 * K, fill=c, outline=INK, width=lw(7))


def icon_cart(d, c):
    d.line([P(120, 166), P(166, 166), P(196, 316), P(356, 316)], fill=INK, width=lw(12), joint="curve")
    d.polygon([P(176, 196), P(380, 196), P(356, 286), P(196, 286)], fill=c, outline=INK)
    for x in (212, 336):
        d.ellipse(box(x - 18, 336, x + 18, 372), fill=INK)


def icon_phone(d, c):
    d.rounded_rectangle(box(186, 126, 326, 386), radius=26 * K, fill=INK)
    d.rounded_rectangle(box(198, 156, 314, 344), radius=8 * K, fill=C["sky"])
    d.ellipse(box(246, 352, 266, 372), fill=C["grey"])


def icon_mail(d, c):
    d.rectangle(box(136, 186, 376, 336), fill=C["white"], outline=INK, width=lw(9))
    d.line([P(140, 190), P(256, 276), P(372, 190)], fill=c, width=lw(12), joint="curve")


def icon_paw(d, c):
    d.ellipse(box(196, 256, 316, 356), fill=C["brown"])
    for x, y in ((176, 216), (226, 176), (286, 176), (336, 216)):
        d.ellipse(box(x - 26, y - 30, x + 26, y + 30), fill=C["brown"])


def icon_plant(d, c):
    d.polygon([P(196, 296), P(316, 296), P(300, 386), P(212, 386)], fill=C["coral"], outline=INK)
    d.line([P(256, 296), P(256, 196)], fill=C["green"], width=lw(10))
    d.ellipse(box(176, 176, 256, 226), fill=C["green"])
    d.ellipse(box(256, 146, 336, 196), fill=C["green"])
    d.ellipse(box(196, 236, 256, 276), fill=C["green"])


ICONS = {
    "calendar": (icon_calendar, "sky"), "clock": (icon_clock, "coral"), "bell": (icon_bell, "sun"),
    "phone": (icon_phone, "lilac"), "mail": (icon_mail, "rose"), "cart": (icon_cart, "mint"),
    "dumbbell": (icon_dumbbell, "sky"), "heart": (icon_heart, "rose"), "star": (icon_star, "lilac"),
    "house": (icon_house, "mint"), "car": (icon_car, "sky"), "plane": (icon_plane, "peach"),
    "book": (icon_book, "coral"), "pencil": (icon_pencil, "mint"), "cake": (icon_cake, "lilac"),
    "gift": (icon_gift, "rose"), "coffee": (icon_coffee, "sand"), "pill": (icon_pill, "coral"),
    "money": (icon_dollar, "mint"), "music": (icon_music, "lilac"), "camera": (icon_camera, "peach"),
    "check": (icon_check, "green"), "flag": (icon_flag, "coral"), "idea": (icon_bulb, "sky"),
    "pet": (icon_paw, "sand"), "plant": (icon_plant, "peach"),
}


def icon_sticker(name, background=None):
    draw, bg = ICONS[name]
    im, d = canvas()
    badge(d, C[background or bg] if name != "check" else C["green"])
    out = draw(d, C[bg])
    if isinstance(out, Image.Image):
        im.alpha_composite(out)
    return finish(im)


# Washi tape


def tape(pattern, base, accent):
    w, h = 1024, 200
    im, d = canvas(w, h)
    d.rectangle(box(0, 30, w, h - 30), fill=base + (225,))
    if pattern == "stripes":
        for x in range(-200, w + 200, 48):
            d.polygon([P(x, 30), P(x + 24, 30), P(x + 24 - 70, h - 30), P(x - 70, h - 30)], fill=accent + (225,))
    elif pattern == "dots":
        for row, y in enumerate((62, 100, 138)):
            for x in range(20 + (row % 2) * 24, w, 48):
                d.ellipse(box(x - 9, y - 9, x + 9, y + 9), fill=accent + (235,))
    elif pattern == "grid":
        for x in range(0, w, 28):
            d.line([P(x, 30), P(x, h - 30)], fill=accent + (180,), width=lw(3))
        for y in range(30, h - 30, 28):
            d.line([P(0, y), P(w, y)], fill=accent + (180,), width=lw(3))
    elif pattern == "zigzag":
        for y0 in (70, 120):
            pts = [P(x, y0 + (14 if (x // 30) % 2 else -14)) for x in range(0, w + 30, 30)]
            d.line(pts, fill=accent + (235,), width=lw(8))
    elif pattern == "hearts":
        for i, x in enumerate(range(40, w, 80)):
            d.polygon(heart_pts(x, 100 + (16 if i % 2 else -16), 26), fill=accent + (235,))
    elif pattern == "stars":
        for i, x in enumerate(range(40, w, 80)):
            d.polygon(star_pts(x, 100 + (16 if i % 2 else -16), 26), fill=accent + (235,))
    elif pattern == "check":
        for x in range(0, w, 40):
            for y in range(30, h - 30, 40):
                if (x // 40 + y // 40) % 2:
                    d.rectangle(box(x, y, x + 40, min(y + 40, h - 30)), fill=accent + (200,))
    elif pattern == "plain":
        d.line([P(0, 46), P(w, 46)], fill=accent + (150,), width=lw(4))
        d.line([P(0, h - 46), P(w, h - 46)], fill=accent + (150,), width=lw(4))
    # Torn ends.
    erase = Image.new("L", im.size, 255)
    ed = ImageDraw.Draw(erase)
    for edge in (0, w):
        pts = []
        for k, y in enumerate(range(20, h - 19, 12)):
            dx = (10 if k % 2 else 0)
            pts.append(P(edge + (dx if edge == 0 else -dx), y))
        if edge == 0:
            ed.polygon([P(0, 0)] + pts + [P(0, h)], fill=0)
        else:
            ed.polygon([P(w, 0)] + pts + [P(w, h)], fill=0)
    im.putalpha(Image.composite(im.getchannel("A"), Image.new("L", im.size, 0), erase))
    return finish(im)


TAPES = [
    ("stripes", "peach", "white"), ("dots", "mint", "white"), ("grid", "sand", "white"), ("zigzag", "sky", "white"),
    ("hearts", "rose", "white"), ("stars", "navy", "sun"), ("check", "lilac", "white"), ("plain", "sun", "white"),
    ("stripes", "sage", "white"), ("dots", "coral", "sun"), ("grid", "sky", "navy"), ("zigzag", "rose", "sun"),
    ("hearts", "white", "rose"), ("stars", "lilac", "white"), ("check", "mint", "white"), ("plain", "coral", "white"),
    ("stripes", "navy", "sky"), ("dots", "sand", "brown"), ("plain", "sage", "white"), ("check", "peach", "white"),
]


# Labels


def label(text, fill, shape="pill", ink=INK, w=640, h=220):
    im, d = canvas(w, h)
    if shape == "pill":
        d.rounded_rectangle(box(8, 8, w - 8, h - 8), radius=(h / 2 - 8) * K, fill=C["white"])
        d.rounded_rectangle(box(22, 22, w - 22, h - 22), radius=(h / 2 - 22) * K, fill=fill)
    elif shape == "banner":
        d.polygon([P(8, 30), P(w - 8, 30), P(w - 60, h / 2), P(w - 8, h - 30), P(8, h - 30), P(60, h / 2)], fill=C["white"])
        d.polygon([P(26, 44), P(w - 30, 44), P(w - 78, h / 2), P(w - 30, h - 44), P(26, h - 44), P(74, h / 2)], fill=fill)
    elif shape == "tab":
        d.rounded_rectangle(box(8, 8, w - 8, h + 60), radius=40 * K, fill=C["white"])
        d.rounded_rectangle(box(22, 22, w - 22, h + 60), radius=30 * K, fill=fill)
    elif shape == "box":
        d.rectangle(box(8, 8, w - 8, h - 8), fill=C["white"])
        d.rectangle(box(22, 22, w - 22, h - 22), fill=fill)
        d.rectangle(box(36, 36, w - 36, h - 36), outline=ink, width=lw(4))
    size = 78 if len(text) < 10 else 62
    d.text(P(w / 2, h / 2 + 2), text, font=font(size * K), fill=ink, anchor="mm")
    return finish(im)


LABEL_WORDS = [("To do", "sun"), ("Notes", "sky"), ("Important", "coral"), ("Due", "rose"), ("Done!", "mint"),
               ("Ideas", "lilac"), ("Goals", "peach"), ("This week", "sage"), ("Today", "sun"), ("Remember", "rose"),
               ("Meeting", "sky"), ("Birthday", "lilac"), ("Payday", "mint"), ("Appointment", "peach"),
               ("Deadline", "coral"), ("Weekend", "sand")]


# Faces


def face(kind):
    im, d = canvas()
    yellow, dark = (250, 206, 84), (90, 62, 40)
    d.ellipse(box(26, 26, 486, 486), fill=C["white"])
    d.ellipse(box(44, 44, 468, 468), fill=yellow)
    eye = lambda x, y, r=22: d.ellipse(box(x - r, y - r, x + r, y + r), fill=dark)  # noqa: E731
    cheeks = lambda: [d.ellipse(box(x - 34, 296, x + 34, 330), fill=(246, 150, 130)) for x in (150, 362)]  # noqa: E731
    if kind in ("smile", "blush", "nervous", "sick", "tired", "neutral", "sad", "cry", "angry", "surprised", "silly",
                "sleepy", "party"):
        if kind in ("sleepy", "tired"):
            for x in (190, 322):
                d.arc(box(x - 30, 196, x + 30, 246), 0, 180, fill=dark, width=lw(10))
        elif kind == "angry":
            eye(190, 236)
            eye(322, 236)
            d.line([P(150, 180), P(222, 210)], fill=dark, width=lw(12))
            d.line([P(362, 180), P(290, 210)], fill=dark, width=lw(12))
        else:
            eye(190, 222)
            eye(322, 222)
    if kind == "smile":
        d.arc(box(156, 220, 356, 380), 20, 160, fill=dark, width=lw(14))
    elif kind == "grin":
        for x in (190, 322):
            d.arc(box(x - 34, 196, x + 34, 256), 200, 340, fill=dark, width=lw(12))
        d.chord(box(146, 240, 366, 400), 0, 180, fill=dark)
        d.chord(box(176, 250, 336, 300), 0, 180, fill=C["white"])
    elif kind == "laugh":
        for x in (190, 322):
            d.line([P(x - 30, 200), P(x + 20, 222), P(x - 30, 244)], fill=dark, width=lw(12), joint="curve")
        d.chord(box(146, 250, 366, 410), 0, 180, fill=dark)
        d.ellipse(box(66, 230, 116, 300), fill=C["sky"])
        d.ellipse(box(396, 230, 446, 300), fill=C["sky"])
    elif kind == "wink":
        eye(190, 222)
        d.arc(box(292, 200, 352, 250), 200, 340, fill=dark, width=lw(12))
        d.arc(box(156, 220, 356, 380), 20, 160, fill=dark, width=lw(14))
    elif kind == "love":
        for x in (190, 322):
            d.polygon(heart_pts(x, 224, 50), fill=C["red"])
        d.arc(box(156, 230, 356, 390), 20, 160, fill=dark, width=lw(14))
    elif kind == "blush":
        cheeks()
        d.arc(box(196, 260, 316, 350), 20, 160, fill=dark, width=lw(12))
    elif kind == "sad":
        d.arc(box(176, 320, 336, 420), 200, 340, fill=dark, width=lw(14))
    elif kind == "cry":
        d.arc(box(176, 320, 336, 420), 200, 340, fill=dark, width=lw(14))
        d.polygon([P(176, 250), P(156, 310), P(196, 310)], fill=C["sky"])
        d.ellipse(box(156, 292, 196, 332), fill=C["sky"])
    elif kind == "angry":
        d.arc(box(176, 320, 336, 420), 200, 340, fill=dark, width=lw(14))
    elif kind == "tired":
        d.line([P(206, 340), P(306, 340)], fill=dark, width=lw(14))
        d.text(P(380, 130), "z", font=font(70 * K), fill=C["navy"], anchor="mm")
    elif kind == "sleepy":
        d.ellipse(box(226, 310, 286, 370), outline=dark, width=lw(12))
        d.text(P(370, 120), "Zz", font=font(80 * K), fill=C["navy"], anchor="mm")
    elif kind == "sick":
        d.rounded_rectangle(box(156, 280, 356, 380), radius=20 * K, fill=C["white"], outline=(180, 190, 200), width=lw(6))
        d.line([P(156, 300), P(80, 260)], fill=C["white"], width=lw(8))
        d.line([P(356, 300), P(432, 260)], fill=C["white"], width=lw(8))
    elif kind == "cool":
        d.rounded_rectangle(box(126, 186, 246, 262), radius=24 * K, fill=dark)
        d.rounded_rectangle(box(266, 186, 386, 262), radius=24 * K, fill=dark)
        d.line([P(246, 210), P(266, 210)], fill=dark, width=lw(10))
        d.arc(box(176, 260, 336, 370), 20, 160, fill=dark, width=lw(14))
    elif kind == "surprised":
        d.ellipse(box(216, 300, 296, 390), fill=dark)
    elif kind == "neutral":
        d.line([P(186, 340), P(326, 340)], fill=dark, width=lw(14))
    elif kind == "nervous":
        pts = [P(176 + k * 20, 340 + (12 if k % 2 else -12)) for k in range(9)]
        d.line(pts, fill=dark, width=lw(10))
        d.ellipse(box(380, 120, 420, 180), fill=C["sky"])
    elif kind == "silly":
        d.arc(box(156, 220, 356, 360), 20, 160, fill=dark, width=lw(14))
        d.chord(box(236, 320, 316, 410), 0, 180, fill=(236, 110, 120))
    elif kind == "party":
        d.arc(box(156, 220, 356, 380), 20, 160, fill=dark, width=lw(14))
        d.polygon([P(300, 100), P(400, 40), P(380, 160)], fill=C["lilac"])
        for x, y, col in ((90, 120, "coral"), (430, 260, "mint"), (120, 420, "sky"), (400, 400, "rose")):
            d.rectangle(box(x, y, x + 22, y + 22), fill=C[col])
    elif kind == "starstruck":
        for x in (190, 322):
            d.polygon(star_pts(x, 222, 44), fill=C["white"])
            d.polygon(star_pts(x, 222, 34), fill=C["orange"])
        d.chord(box(176, 260, 336, 390), 0, 180, fill=dark)
    elif kind == "think":
        eye(190, 222)
        eye(322, 222)
        d.line([P(206, 340), P(316, 326)], fill=dark, width=lw(12))
        d.ellipse(box(330, 330, 420, 420), fill=yellow, outline=dark, width=lw(8))
    return finish(im)


FACES = ["smile", "grin", "laugh", "wink", "love", "blush", "starstruck", "party", "cool", "silly", "think", "neutral",
         "surprised", "nervous", "tired", "sleepy", "sad", "cry", "angry", "sick"]


# Weather and moon


def weather(kind):
    im, d = canvas()
    badge(d, (232, 240, 250))

    def sun(cx, cy, r):
        for i in range(12):
            a = i * math.pi / 6
            d.line([P(cx + r * 1.3 * math.cos(a), cy + r * 1.3 * math.sin(a)),
                    P(cx + r * 1.65 * math.cos(a), cy + r * 1.65 * math.sin(a))], fill=C["orange"], width=lw(14))
        d.ellipse(box(cx - r, cy - r, cx + r, cy + r), fill=C["sun"])

    def cloud(cx, cy, s=1.0, col=C["white"]):
        for dx, dy, r in ((-60, 10, 52), (0, -24, 70), (66, 8, 50)):
            d.ellipse(box(cx + (dx - r) * s, cy + (dy - r) * s, cx + (dx + r) * s, cy + (dy + r) * s), fill=col)
        d.rounded_rectangle(box(cx - 110 * s, cy, cx + 114 * s, cy + 56 * s), radius=28 * s * K, fill=col)

    if kind == "sunny":
        sun(256, 256, 84)
    elif kind == "partly":
        sun(206, 206, 64)
        cloud(286, 290, 0.95)
    elif kind == "cloudy":
        cloud(226, 230, 0.8, (205, 212, 224))
        cloud(276, 290, 1.0)
    elif kind == "rain":
        cloud(256, 220, 1.0, (190, 200, 216))
        for x in (186, 246, 306):
            d.line([P(x + 10, 310), P(x - 10, 370)], fill=C["sky"], width=lw(14))
    elif kind == "storm":
        cloud(256, 210, 1.0, (150, 160, 180))
        d.polygon([P(266, 290), P(222, 360), P(258, 360), P(236, 420), P(304, 336), P(268, 336), P(292, 290)],
                  fill=C["sun"])
    elif kind == "snow":
        cloud(256, 210, 1.0, (210, 218, 230))
        for x, y in ((196, 330), (256, 370), (316, 330)):
            for a in range(3):
                ang = a * math.pi / 3
                d.line([P(x - 20 * math.cos(ang), y - 20 * math.sin(ang)), P(x + 20 * math.cos(ang), y + 20 * math.sin(ang))],
                       fill=C["sky"], width=lw(7))
    elif kind == "wind":
        for y, w in ((206, 220), (256, 260), (306, 190)):
            d.line([P(126, y), P(126 + w, y)], fill=C["sky"], width=lw(16))
            d.arc(box(126 + w - 30, y - 60, 126 + w + 30, y), 270, 180, fill=C["sky"], width=lw(16))
    elif kind == "rainbow":
        for k, col in enumerate(("red", "orange", "sun", "green", "sky", "lilac")):
            r = 170 - k * 20
            d.arc(box(256 - r, 330 - r, 256 + r, 330 + r), 180, 360, fill=C[col], width=lw(20))
        cloud(126, 330, 0.55)
        cloud(386, 330, 0.55)
    elif kind == "hot":
        d.rounded_rectangle(box(226, 120, 286, 330), radius=30 * K, fill=C["white"], outline=INK, width=lw(8))
        d.ellipse(box(206, 300, 306, 400), fill=C["red"], outline=INK, width=lw(8))
        d.rectangle(box(244, 180, 268, 320), fill=C["red"])
    elif kind.startswith("moon"):
        d.ellipse(box(36, 36, 476, 476), fill=C["navy"])
        phase = int(kind[-1])  # 0 new .. 4 full .. 7
        d.ellipse(box(146, 146, 366, 366), fill=(70, 88, 136))
        lit = Image.new("L", im.size, 0)
        ld = ImageDraw.Draw(lit)
        ld.ellipse(box(146, 146, 366, 366), fill=255)
        frac = math.cos(phase / 8 * 2 * math.pi)  # 1 new, -1 full
        shade = Image.new("L", im.size, 0)
        sd = ImageDraw.Draw(shade)
        if phase in (1, 2, 3):  # waxing: lit on the right
            sd.rectangle(box(146, 146, 256, 366), fill=255)
        elif phase in (5, 6, 7):
            sd.rectangle(box(256, 146, 366, 366), fill=255)
        elif phase == 0:
            sd.rectangle(box(146, 146, 366, 366), fill=255)
        ew = abs(frac) * 110
        if phase in (1, 7):
            sd.ellipse(box(256 - ew, 146, 256 + ew, 366), fill=255)
        elif phase in (3, 5):
            sd.ellipse(box(256 - ew, 146, 256 + ew, 366), fill=0)
        mask = Image.composite(Image.new("L", im.size, 0), lit, shade)
        im.paste((246, 236, 200, 255), (0, 0), mask)
    return finish(im)


WEATHER = ["sunny", "partly", "cloudy", "rain", "storm", "snow", "wind", "rainbow", "hot",
           "moon0", "moon1", "moon2", "moon3", "moon4", "moon5", "moon6", "moon7"]
WEATHER_NAMES = {"moon0": "New moon", "moon1": "Waxing crescent", "moon2": "First quarter", "moon3": "Waxing gibbous",
                 "moon4": "Full moon", "moon5": "Waning gibbous", "moon6": "Last quarter", "moon7": "Waning crescent",
                 "partly": "Partly cloudy"}


# Seasonal


def seasonal(kind):
    im, d = canvas()
    if kind == "pumpkin":
        for dx in (-70, 70, 0):
            d.ellipse(box(256 + dx - 110, 170, 256 + dx + 110, 400), fill=C["orange"], outline=(200, 110, 40), width=lw(6))
        d.rounded_rectangle(box(240, 120, 272, 180), radius=8 * K, fill=C["green"])
    elif kind == "snowflake":
        for a in range(6):
            ang = a * math.pi / 3
            x, y = 256 + 190 * math.cos(ang), 256 + 190 * math.sin(ang)
            d.line([P(256, 256), P(x, y)], fill=C["sky"], width=lw(22))
            for t in (0.55, 0.8):
                bx, by = 256 + 190 * t * math.cos(ang), 256 + 190 * t * math.sin(ang)
                for s in (-1, 1):
                    a2 = ang + s * math.pi / 4
                    d.line([P(bx, by), P(bx + 50 * math.cos(a2), by + 50 * math.sin(a2))], fill=C["sky"], width=lw(16))
    elif kind == "tree":
        for k, (y, w) in enumerate(((130, 120), (200, 160), (270, 200))):
            d.polygon([P(256, y - 60), P(256 + w, y + 90), P(256 - w, y + 90)], fill=C["green"])
        d.rectangle(box(226, 360, 286, 420), fill=C["brown"])
        d.polygon(star_pts(256, 80, 44), fill=C["sun"])
        for x, y, col in ((206, 230, "red"), (306, 280, "sun"), (226, 330, "sky"), (326, 360, "red"), (186, 330, "sun")):
            d.ellipse(box(x - 16, y - 16, x + 16, y + 16), fill=C[col])
    elif kind == "gift":
        icon_gift(d, C["red"])
    elif kind == "heart":
        d.polygon(heart_pts(256, 266, 200), fill=C["rose"])
        d.polygon(heart_pts(256, 266, 150), fill=C["red"])
    elif kind == "clover":
        for ang in (-90, 30, 150):
            a = math.radians(ang)
            cx, cy = 256 + 80 * math.cos(a), 236 + 80 * math.sin(a)
            d.polygon(heart_pts(cx, cy, 90), fill=C["green"])
        d.line([P(256, 260), P(300, 440)], fill=C["green"], width=lw(18))
    elif kind == "egg":
        d.ellipse(box(146, 86, 366, 436), fill=C["lilac"])
        for y, col in ((200, "sun"), (280, "mint"), (360, "rose")):
            pts = [P(150 + k * 22, y + (14 if k % 2 else -14)) for k in range(11)]
            d.line(pts, fill=C[col], width=lw(16))
    elif kind == "flower":
        for k in range(6):
            a = k * math.pi / 3
            cx, cy = 256 + 110 * math.cos(a), 256 + 110 * math.sin(a)
            d.ellipse(box(cx - 80, cy - 80, cx + 80, cy + 80), fill=C["rose"])
        d.ellipse(box(196, 196, 316, 316), fill=C["sun"])
    elif kind == "leaf":
        pts = []
        for i in range(60):
            t = i / 60 * 2 * math.pi
            x, y = 200 * math.cos(t), 110 * math.sin(t) * (1 - 0.3 * math.cos(t))
            a = -math.pi / 4
            pts.append(P(256 + x * math.cos(a) - y * math.sin(a), 256 + x * math.sin(a) + y * math.cos(a)))
        d.polygon(pts, fill=C["orange"])
        d.line([P(120, 392), P(390, 122)], fill=(190, 100, 40), width=lw(10))
    elif kind == "sun":
        d.ellipse(box(146, 146, 366, 366), fill=C["sun"])
        for i in range(12):
            a = i * math.pi / 6
            d.polygon([P(256 + 130 * math.cos(a - 0.15), 256 + 130 * math.sin(a - 0.15)),
                       P(256 + 220 * math.cos(a), 256 + 220 * math.sin(a)),
                       P(256 + 130 * math.cos(a + 0.15), 256 + 130 * math.sin(a + 0.15))], fill=C["orange"])
    elif kind == "umbrella":
        d.pieslice(box(76, 106, 436, 406), 180, 360, fill=C["coral"])
        for k in range(4):
            x = 76 + k * 90
            d.chord(box(x, 220, x + 90, 290), 180, 360, fill=(0, 0, 0, 0))
        d.line([P(256, 256), P(256, 400)], fill=INK, width=lw(14))
        d.arc(box(196, 370, 256, 430), 0, 180, fill=INK, width=lw(14))
    elif kind == "firework":
        for i in range(16):
            a = i * math.pi / 8
            col = (C["sun"], C["rose"], C["sky"], C["mint"])[i % 4]
            d.line([P(256 + 60 * math.cos(a), 256 + 60 * math.sin(a)), P(256 + 200 * math.cos(a), 256 + 200 * math.sin(a))],
                   fill=col, width=lw(14))
            d.ellipse(box(256 + 210 * math.cos(a) - 12, 256 + 210 * math.sin(a) - 12,
                          256 + 210 * math.cos(a) + 12, 256 + 210 * math.sin(a) + 12), fill=col)
    elif kind == "candle":
        d.rectangle(box(216, 220, 296, 430), fill=C["sky"])
        d.ellipse(box(226, 110, 286, 210), fill=C["sun"])
        d.ellipse(box(242, 150, 270, 200), fill=C["orange"])
        d.line([P(256, 200), P(256, 222)], fill=INK, width=lw(6))
    elif kind == "ghost":
        d.pieslice(box(136, 86, 376, 326), 180, 360, fill=C["white"])
        d.rectangle(box(136, 204, 376, 400), fill=C["white"])
        for k in range(4):
            d.ellipse(box(136 + k * 60, 370, 196 + k * 60, 430), fill=C["white"])
        d.ellipse(box(196, 200, 236, 250), fill=INK)
        d.ellipse(box(276, 200, 316, 250), fill=INK)
        out = Image.new("RGBA", im.size, (0, 0, 0, 0))
        ImageDraw.Draw(out).ellipse(box(120, 70, 392, 446), fill=(200, 200, 215, 255))
        out.alpha_composite(im)
        im = out
    elif kind == "balloon":
        d.ellipse(box(156, 66, 356, 316), fill=C["red"])
        d.polygon([P(256, 310), P(236, 340), P(276, 340)], fill=C["red"])
        d.line([P(256, 340), P(236, 400), P(270, 450)], fill=INK, width=lw(6), joint="curve")
        d.ellipse(box(196, 110, 236, 170), fill=(255, 180, 180))
    return finish(im)


SEASONAL = ["heart", "clover", "egg", "flower", "sun", "umbrella", "firework", "leaf", "pumpkin", "ghost", "snowflake",
            "tree", "gift", "candle", "balloon"]


# Packs


def white_edge(im, width=10):
    """Adds a white sticker border around any shape."""
    a = im.getchannel("A")
    from PIL import ImageFilter
    grown = a.filter(ImageFilter.MaxFilter(width * 2 + 1))
    base = Image.new("RGBA", im.size, (255, 255, 255, 0))
    base.putalpha(grown)
    base.alpha_composite(im)
    return base


def study_words():
    return [("Exam", "coral"), ("Quiz", "sun"), ("Homework", "sky"), ("Study", "mint"), ("Read", "lilac"),
            ("Lab", "peach"), ("Project", "rose"), ("Group work", "sage"), ("Office hours", "sand"), ("Class", "sky")]


def pack_items(pid):
    """(file name, display name, image) for each sticker in [pid]."""
    out = []
    if pid == "stickers_planner_icons":
        for name in ICONS:
            out.append((name, name.capitalize(), icon_sticker(name)))
    elif pid == "stickers_washi":
        for i, (pattern, base, accent) in enumerate(TAPES):
            out.append((f"tape_{i + 1}", f"{base.capitalize()} {pattern}", tape(pattern, C[base], C[accent])))
    elif pid == "stickers_labels":
        shapes = ["pill", "banner", "tab", "box"]
        for i, (word, col) in enumerate(LABEL_WORDS):
            name = word.lower().replace(" ", "_").replace("!", "")
            out.append((name, word, label(word, C[col], shapes[i % 4])))
    elif pid == "stickers_study":
        for word, col in study_words():
            name = word.lower().replace(" ", "_")
            out.append((name, word, label(word, C[col], "pill")))
        for name in ("book", "pencil", "idea", "calendar", "clock", "check", "flag", "coffee", "star", "music"):
            out.append((f"icon_{name}", name.capitalize(), icon_sticker(name)))
    elif pid == "stickers_seasonal":
        for kind in SEASONAL:
            out.append((kind, kind.capitalize(), white_edge(seasonal(kind))))
    elif pid == "stickers_emoji":
        for kind in FACES:
            out.append((kind, kind.capitalize(), face(kind)))
    elif pid == "stickers_weather":
        for kind in WEATHER:
            out.append((kind, WEATHER_NAMES.get(kind, kind.capitalize()), weather(kind)))
    return out


PACKS = {
    "stickers_planner_icons": ("Planner Icons", ["icons", "planner", "everyday"], "1.99"),
    "stickers_washi": ("Washi Tape", ["washi", "tape", "decor"], "1.99"),
    "stickers_labels": ("Labels & Tabs", ["labels", "banners", "headers"], "1.99"),
    "stickers_study": ("Study Stickers", ["school", "study", "labels"], "1.99"),
    "stickers_seasonal": ("Seasons & Holidays", ["holidays", "seasons", "festive"], "1.99"),
    "stickers_emoji": ("Faces", ["emoji", "mood", "faces"], "1.99"),
    "stickers_weather": ("Weather & Moon", ["weather", "moon", "sky"], "1.99"),
}


def write(pid):
    name, tags, _ = PACKS[pid]
    folder = ROOT / "catalog" / pid
    (folder / "stickers").mkdir(parents=True, exist_ok=True)
    for old in (folder / "stickers").glob("*.webp"):
        old.unlink()
    entries = []
    items = pack_items(pid)
    for file, title, im in items:
        im.save(folder / "stickers" / f"{file}.webp", "WEBP", lossless=True)
        entries.append({"file": f"stickers/{file}.webp", "name": title})
    (folder / "stickers.json").write_text(json.dumps({"stickers": entries}, indent=2) + "\n")
    prev = Image.new("RGB", (512, 384), (246, 244, 239))
    wide = items[0][2].width > items[0][2].height * 1.5
    cols, cell = (2, (240, 70)) if wide else (4, (110, 110))
    for n, (_, _, im) in enumerate(items[: (10 if wide else 12)]):
        s = im.copy()
        s.thumbnail(cell)
        x = 16 + (n % cols) * (cell[0] + 8)
        y = 16 + (n // cols) * (cell[1] + 6)
        prev.paste(s, (x + (cell[0] - s.width) // 2, y + (cell[1] - s.height) // 2), s)
    prev.save(folder / "preview.webp", "WEBP", quality=88)
    listing = {
        "kind": "stickers",
        "name": name,
        "version": 1,
        "unlock": {"pro": True, "products": [f"pack_{pid}"]},
        "category": "stickers",
        "tags": tags,
    }
    path = folder / "listing.json"
    if path.exists():
        listing["version"] = json.loads(path.read_text()).get("version", 1)
    path.write_text(json.dumps(listing, indent=2) + "\n")
    return len(items)


def main():
    args = sys.argv[1:]
    if len(args) != 1 or (args[0] != "all" and args[0] not in PACKS):
        sys.exit(__doc__)
    for pid in PACKS if args[0] == "all" else args:
        print(f"{pid}: {write(pid)} stickers")


if __name__ == "__main__":
    main()

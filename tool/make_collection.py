"""Makes a whole collection's catalog items from its style in
tool/collections.json, all drawn in code:

  python3 tool/make_collection.py botanical               # one collection
  python3 tool/make_collection.py all                     # every collection
  python3 tool/make_collection.py all --year 2026         # planners only, for 2026

For a collection <id> it writes these catalog folders:

  <id>/                  the collection itself (listing + preview)
  <id>_planner_<year>/   a dated weekly planner in the collection's style
                         (2027 unless --year is given; with --year, only
                         the planner is written)
  <id>_pages/            the page pack: every layout in tool/page_layouts.py
  <id>_cover_1..3/       covers: pattern, label plate, two-tone band
  <id>_paper_<pattern>/  papers, from the style's "papers"
  <id>_stickers/         stickers in the collection's motif and colors

Items unlock with their collection (Pro, or pack_<id>). Re-running keeps
each item's version, so raise "version" in its listing.json by hand when
files change, then check and publish with tool/catalog.py. Needs Pillow,
and macOS `sips` for PDF previews.
"""

import json
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_planner as mp  # noqa: E402
import page_layouts  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "catalog"
SPECS = Path(__file__).resolve().parent / "collections.json"
YEAR = 2027
COVER = (1536, 2048)


def rgb255(hex_):
    hex_ = hex_.lstrip("#")
    return tuple(int(hex_[i:i + 2], 16) for i in (0, 2, 4))


def rgb1(hex_):
    return tuple(c / 255 for c in rgb255(hex_))


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def style_of(spec):
    return mp.Style(
        ink=rgb1(spec["ink"]),
        soft=rgb1(spec["soft"]),
        rule=rgb1(spec["rule"]),
        accent=rgb1(spec["accent"]),
        tab=rgb1(spec["tab"]),
        on_accent=rgb1(spec["onAccent"]),
        paper=rgb1(spec["paper"]),
        border=spec["border"],
        header=spec["header"],
        motif=spec["motif"],
        serif=spec["serif"],
    )


def write_listing(folder, listing):
    """Writes listing.json, keeping the existing version (bumped by hand)."""
    path = folder / "listing.json"
    if path.exists():
        listing["version"] = json.loads(path.read_text()).get("version", 1)
    path.write_text(json.dumps(listing, indent=2) + "\n")


# Shapes, drawn with Pillow (covers, stickers, previews)


def draw_motif(d, kind, cx, cy, size, fill):
    r = size / 2
    if kind == "stars":
        pts = []
        for i in range(10):
            a = -math.pi / 2 + i * math.pi / 5
            rr = r if i % 2 == 0 else r * 0.45
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        d.polygon(pts, fill=fill)
    elif kind == "hearts":
        pts = []
        for i in range(60):
            t = i / 60 * 2 * math.pi
            x = 16 * math.sin(t) ** 3
            y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
            pts.append((cx + x * r / 17, cy - y * r / 17))
        d.polygon(pts, fill=fill)
    elif kind == "leaves":
        pts = []
        for i in range(40):
            t = i / 40 * 2 * math.pi
            x, y = r * math.cos(t), r * 0.45 * math.sin(t) * (1 - 0.3 * math.cos(t))
            a = -math.pi / 4
            pts.append((cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)))
        d.polygon(pts, fill=fill)
    elif kind == "sun":
        d.ellipse((cx - r * 0.45, cy - r * 0.45, cx + r * 0.45, cy + r * 0.45), fill=fill)
        for i in range(10):
            a = i * math.pi / 5
            d.line((cx + r * 0.62 * math.cos(a), cy + r * 0.62 * math.sin(a),
                    cx + r * math.cos(a), cy + r * math.sin(a)), fill=fill, width=max(2, int(size / 14)))
    elif kind == "waves":
        w = max(2, int(size / 12))
        for k in range(3):
            y0 = cy - r * 0.6 + k * r * 0.6
            pts = [(cx - r + j * r / 10, y0 + math.sin(j / 10 * 2 * math.pi) * r * 0.18) for j in range(21)]
            d.line(pts, fill=fill, width=w, joint="curve")
    elif kind == "moons":
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)
    else:  # dots, and a fallback
        d.ellipse((cx - r * 0.5, cy - r * 0.5, cx + r * 0.5, cy + r * 0.5), fill=fill)


def font(size, bold=True):
    names = ["/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
             "/Library/Fonts/Arial Bold.ttf", "DejaVuSans-Bold.ttf"]
    for n in names:
        try:
            return ImageFont.truetype(n, size)
        except OSError:
            continue
    return ImageFont.load_default(size=size)


# Covers


def cover_image(spec, variant, color):
    base = rgb255(color)
    accent = rgb255(spec["accent"])
    second = rgb255(spec["second"])
    light = ThemeLight = mix(base, (255, 255, 255), 0.18)
    dark_base = sum(base) / 3 < 110
    ink_on = (255, 255, 255) if dark_base else mix(base, (0, 0, 0), 0.55)
    im = Image.new("RGB", COVER, base)
    d = ImageDraw.Draw(im)
    w, h = COVER
    motif = spec["motif"] if spec["motif"] != "none" else "dots"
    rnd = random.Random(f"{spec['name']}-{variant}")

    if variant == 1:
        # A scattered pattern of the motif.
        tone = mix(base, ink_on, 0.22)
        step = 210
        for row in range(-1, h // step + 2):
            for col in range(-1, w // step + 2):
                x = col * step + (step / 2 if row % 2 else 0) + rnd.uniform(-20, 20)
                y = row * step + rnd.uniform(-20, 20)
                draw_motif(d, motif, x, y, rnd.uniform(70, 110), tone)
    elif variant == 2:
        # Plain cover with a frame and a label plate.
        frame = mix(base, ink_on, 0.35)
        d.rectangle((90, 90, w - 90, h - 90), outline=frame, width=10)
        d.rectangle((120, 120, w - 120, h - 120), outline=frame, width=3)
        pw, ph = 760, 300
        px, py = (w - pw) / 2, h * 0.32
        d.rounded_rectangle((px, py, px + pw, py + ph), radius=36, fill=mix(base, (255, 255, 255), 0.85))
        d.rounded_rectangle((px + 22, py + 22, px + pw - 22, py + ph - 22), radius=24, outline=accent, width=4)
        if spec["motif"] != "none":
            draw_motif(d, motif, w / 2, h * 0.72, 180, mix(base, ink_on, 0.4))
    else:
        # A two-tone band across the lower third, with an elastic strap.
        band = second if second != base else accent
        d.rectangle((0, h * 0.62, w, h), fill=band)
        d.line((0, h * 0.62, w, h * 0.62), fill=mix(band, (255, 255, 255), 0.4), width=8)
        if spec["motif"] != "none":
            for i in range(5):
                draw_motif(d, motif, w * (0.18 + i * 0.16), h * 0.81, 120, mix(band, (255, 255, 255), 0.35))
        strap = mix(base, (0, 0, 0), 0.35)
        d.rectangle((w - 210, 0, w - 160, h), fill=strap)
    _ = (light, ThemeLight)
    return im


def write_cover(cid, spec, i, color):
    folder = CATALOG / f"{cid}_cover_{i}"
    folder.mkdir(parents=True, exist_ok=True)
    im = cover_image(spec, i, color)
    im.save(folder / "cover.webp", "WEBP", quality=86)
    im.resize((384, 512)).save(folder / "preview.webp", "WEBP", quality=86)
    names = {1: "pattern", 2: "label", 3: "band"}
    write_listing(folder, {
        "kind": "cover",
        "name": f"{spec['name']} {names[i].capitalize()}",
        "version": 1,
        "unlock": {},
        "collectionId": cid,
        "category": "covers",
        "color": color,
        "tags": spec["tags"],
    })


# Stickers


STICKER_WORDS = ["Today", "Done!", "Important", "Yay", "Due", "Remember"]


def sticker_shape(kind, color, size=512):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw_motif(ImageDraw.Draw(im), kind, size / 2, size / 2, size * 0.85, color + (255,))
    return im


def sticker_label(text, fill, ink, size=(640, 240)):
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    w, h = size
    d.rounded_rectangle((6, 6, w - 6, h - 6), radius=h / 2 - 6, fill=fill + (255,))
    d.rounded_rectangle((22, 22, w - 22, h - 22), radius=h / 2 - 22, outline=ink + (255,), width=4)
    f = font(int(h * 0.36))
    tw = d.textlength(text, font=f)
    d.text(((w - tw) / 2, h * 0.28), text, font=f, fill=ink + (255,))
    return im


def write_stickers(cid, spec):
    folder = CATALOG / f"{cid}_stickers"
    (folder / "stickers").mkdir(parents=True, exist_ok=True)
    for old in (folder / "stickers").glob("*.webp"):
        old.unlink()
    accent, second, ink = rgb255(spec["accent"]), rgb255(spec["second"]), rgb255(spec["ink"])
    paper = rgb255(spec["paper"])
    shapes = ["stars", "hearts", "leaves", "sun", "waves", "moons"]
    own = spec["motif"] if spec["motif"] != "none" else "dots"
    shapes = [own] + [s for s in shapes if s != own][:3]
    entries = []
    for i, kind in enumerate(shapes):
        for j, color in enumerate((accent, second)):
            name = f"{kind}_{j + 1}"
            sticker_shape(kind, color).save(folder / "stickers" / f"{name}.webp", "WEBP", lossless=True)
            entries.append({"file": f"stickers/{name}.webp", "name": f"{kind.capitalize()} {j + 1}"})
    label_ink = ink if sum(paper) / 3 > 128 else paper
    for k, word in enumerate(STICKER_WORDS):
        fill = mix(accent if k % 2 == 0 else second, (255, 255, 255), 0.7)
        name = "label_" + word.lower().replace("!", "")
        sticker_label(word, fill, label_ink if sum(fill) / 3 > 128 else (255, 255, 255)).save(
            folder / "stickers" / f"{name}.webp", "WEBP", lossless=True)
        entries.append({"file": f"stickers/{name}.webp", "name": word})
    (folder / "stickers.json").write_text(json.dumps({"stickers": entries}, indent=2) + "\n")

    # Preview: a grid of the first stickers on the collection's paper.
    prev = Image.new("RGB", (512, 384), paper)
    for n, e in enumerate(entries[:12]):
        with Image.open(folder / e["file"]) as s:
            s.thumbnail((110, 110))
            x, y = 16 + (n % 4) * 124, 16 + (n // 4) * 122
            prev.paste(s, (x + (110 - s.width) // 2, y + (110 - s.height) // 2), s)
    prev.save(folder / "preview.webp", "WEBP", quality=88)
    write_listing(folder, {
        "kind": "stickers",
        "name": f"{spec['name']} Stickers",
        "version": 1,
        "unlock": {},
        "collectionId": cid,
        "category": "stickers",
        "tags": spec["tags"],
    })


# Papers


def write_papers(cid, spec):
    for pattern, paper in spec["papers"].items():
        folder = CATALOG / f"{cid}_paper_{pattern}"
        folder.mkdir(parents=True, exist_ok=True)
        write_listing(folder, {
            "kind": "paper",
            "name": f"{spec['name']} {pattern.capitalize()}",
            "version": 1,
            "unlock": {},
            "collectionId": cid,
            "category": "papers",
            "paper": {
                "color": paper["color"],
                "lineColor": paper["lineColor"],
                "marginColor": None,
                "pattern": pattern,
                "spacing": paper["spacing"],
            },
            "tags": spec["tags"],
        })


# Templates


def write_template(folder, pages, spec_json):
    folder.mkdir(parents=True, exist_ok=True)
    mp.write_pdf(pages, folder / "template.pdf")
    (folder / "template.json").write_text(json.dumps(spec_json, indent=2) + "\n")
    mp.write_preview(folder / "template.pdf", folder / "preview.webp")


def write_planner(cid, spec, year):
    mp.use_style(style_of(spec))
    try:
        pages, tspec = mp.planner(year)
        folder = CATALOG / f"{cid}_planner_{year}"
        write_template(folder, pages, tspec)
        write_listing(folder, {
            "kind": "template",
            "name": f"{spec['name']} {year} Planner",
            "version": 1,
            "unlock": {},
            "collectionId": cid,
            "category": "planners",
            "tags": spec["tags"] + ["dated", "weekly", str(year)],
        })
    finally:
        mp.use_style(mp.DEFAULT)


def write_templates(cid, spec):
    write_planner(cid, spec, YEAR)
    mp.use_style(style_of(spec))
    try:

        pages, tspec = page_layouts.pack()
        folder = CATALOG / f"{cid}_pages"
        write_template(folder, pages, tspec)
        write_listing(folder, {
            "kind": "template",
            "name": f"{spec['name']} Pages",
            "version": 1,
            "unlock": {},
            "collectionId": cid,
            "category": "pages",
            "tags": spec["tags"] + ["trackers", "planning", "study"],
        })
    finally:
        mp.use_style(mp.DEFAULT)


# The collection


def write_collection(cid, spec):
    folder = CATALOG / cid
    folder.mkdir(parents=True, exist_ok=True)
    # Preview: the pattern cover beside the first page of the page pack.
    prev = Image.new("RGB", (512, 320), mix(rgb255(spec["paper"]), (0, 0, 0), 0.06))
    with Image.open(CATALOG / f"{cid}_cover_1" / "cover.webp") as c:
        prev.paste(c.resize((210, 280)), (24, 20))
    with Image.open(CATALOG / f"{cid}_pages" / "preview.webp") as p:
        p = p.convert("RGB")
        p.thumbnail((240, 300))
        prev.paste(p, (256, (320 - p.height) // 2))
    prev.save(folder / "preview.webp", "WEBP", quality=88)
    write_listing(folder, {
        "kind": "collection",
        "name": spec["name"],
        "version": 1,
        "unlock": {"pro": True, "products": [f"pack_{cid}"]},
        "tags": spec["tags"],
    })


def make(cid, spec):
    write_templates(cid, spec)
    for i, color in enumerate(spec["covers"], start=1):
        write_cover(cid, spec, i, color)
    write_papers(cid, spec)
    write_stickers(cid, spec)
    write_collection(cid, spec)
    print(f"{cid}: planner, {len(page_layouts.LAYOUTS)} pages, {len(spec['covers'])} covers, "
          f"{len(spec['papers'])} papers, stickers")


def main():
    specs = json.loads(SPECS.read_text())["collections"]
    args = sys.argv[1:]
    year = None
    if len(args) == 3 and args[1] == "--year" and args[2].isdigit():
        year, args = int(args[2]), args[:1]
    if len(args) != 1 or (args[0] != "all" and args[0] not in specs):
        sys.exit(__doc__ + f"\nCollections: {', '.join(specs)}")
    for cid in specs if args[0] == "all" else [args[0]]:
        if year is None:
            make(cid, specs[cid])
        else:
            write_planner(cid, specs[cid], year)
            print(f"{cid}: {year} planner")


if __name__ == "__main__":
    main()

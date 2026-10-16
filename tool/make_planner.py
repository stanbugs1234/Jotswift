"""Makes Jotswift's own PDF templates, with links between pages.
The planner itself is laid out by planner_nav.

  python3 tool/make_planner.py planner 2027   # catalog/planner_2027/
  python3 tool/make_planner.py planner 2026 --span   # Oct 2026 - Dec 2027: catalog/planner_2026_27/
  python3 tool/make_planner.py essentials     # catalog/essentials_pages/

Each run writes template.pdf and template.json into the catalog folder,
plus preview.webp (needs macOS `sips` and Pillow). Write listing.json by
hand, then check and publish with tool/catalog.py.

The PDF is written directly (vector lines, the built-in Helvetica font and
link annotations), so nothing beyond the standard library is needed.
"""

import calendar
import datetime as dt
import json
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

W, H = 612, 792  # US Letter, in points


class Style:
    """The look of a template: colors (RGB 0-1), and for collections a
    page color, border, header style, motif and font. The default is
    Jotswift's plain look, used by the free planner and Essentials."""

    def __init__(
        self,
        ink=(0.12, 0.14, 0.19),
        soft=(0.55, 0.6, 0.68),
        rule=(0.79, 0.84, 0.92),
        accent=(0.17, 0.29, 0.49),
        tab=(0.93, 0.95, 0.98),
        on_accent=(1, 1, 1),
        paper=None,
        border="none",
        header="plain",
        motif="none",
        serif=False,
    ):
        self.ink, self.soft, self.rule = ink, soft, rule
        self.accent, self.tab, self.on_accent = accent, tab, on_accent
        self.paper = paper  # None: white, drawn as nothing
        self.border = border  # none, double, dashed, stitched, hand
        self.header = header  # plain, banner, underline, swash
        self.motif = motif  # none, leaves, stars, hearts, dots, sun, waves
        self.serif = serif  # Times instead of Helvetica


DEFAULT = Style()
S = DEFAULT  # the style pages are drawn in; see use_style()


def use_style(style):
    global S
    S = style

# Helvetica character widths (per 1000 units), for centering and fitting.
_NARROW = set("iljtfrI.,:;'!|() ")
_WIDE = set("mwMW@%")


def text_width(s, size):
    total = 0
    for ch in s:
        total += 278 if ch in _NARROW else 889 if ch in _WIDE else 667 if ch.isupper() else 556
    return total * size / 1000


def use_size(width, height):
    """Pages made after this are [width] x [height] points. Layouts read
    the size through make_planner.W and .H, so set it before drawing."""
    global W, H
    W, H = width, height


class Page:
    def __init__(self):
        self.w, self.h = W, H
        self.ops = []
        self.links = []  # (rect, target page index)
        decorate(self)

    def color(self, rgb, stroke=False):
        self.ops.append("%.3f %.3f %.3f %s" % (*rgb, "RG" if stroke else "rg"))

    def line(self, x0, y0, x1, y1, rgb=None, width=0.8):
        self.color(rgb or S.rule, stroke=True)
        self.ops.append(f"{width} w {x0:.1f} {y0:.1f} m {x1:.1f} {y1:.1f} l S")

    def rect(self, x, y, w, h, fill=None, stroke=None, width=0.8):
        if fill:
            self.color(fill)
        if stroke:
            self.color(stroke, stroke=True)
            self.ops.append(f"{width} w")
        op = "B" if fill and stroke else "f" if fill else "S"
        self.ops.append(f"{x:.1f} {y:.1f} {w:.1f} {h:.1f} re {op}")

    def text(self, x, y, s, size=11, rgb=None, bold=False, center=False, right=False):
        rgb = rgb or S.ink
        if center:
            x -= text_width(s, size) / 2
        elif right:
            x -= text_width(s, size)
        s = s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
        self.color(rgb)
        font = "F2" if bold else "F1"
        self.ops.append(f"BT /{font} {size} Tf {x:.1f} {y:.1f} Td ({s}) Tj ET")

    def link(self, x, y, w, h, target):
        self.links.append(((x, y, x + w, y + h), target))


def tint(rgb, amount):
    """[rgb] mixed toward white by [amount] (0-1)."""
    return tuple(c + (1 - c) * amount for c in rgb)


def _curve(p, pts, rgb, width, fill=False, close=False):
    """A path through Bezier segments: pts = [start, (c1, c2, end), ...]."""
    p.color(rgb, stroke=not fill)
    ops = [f"{pts[0][0]:.1f} {pts[0][1]:.1f} m"]
    for c1, c2, end in pts[1:]:
        ops.append(f"{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {end[0]:.1f} {end[1]:.1f} c")
    if fill:
        p.ops.append(" ".join(ops) + " f")
    else:
        p.ops.append(f"{width} w 1 J " + " ".join(ops) + (" h S" if close else " S"))


def circle(p, x, y, r, rgb, fill=True, width=1):
    k = 0.5523 * r
    _curve(p, [(x + r, y), ((x + r, y + k), (x + k, y + r), (x, y + r)),
               ((x - k, y + r), (x - r, y + k), (x - r, y)),
               ((x - r, y - k), (x - k, y - r), (x, y - r)),
               ((x + k, y - r), (x + r, y - k), (x + r, y))], rgb, width, fill=fill, close=True)


def polygon(p, pts, rgb, fill=True, width=1):
    p.color(rgb, stroke=not fill)
    path = " ".join(f"{x:.1f} {y:.1f} {'m' if i == 0 else 'l'}" for i, (x, y) in enumerate(pts))
    p.ops.append(path + " h f" if fill else f"{width} w 1 j " + path + " h S")


def motif_shape(p, kind, x, y, size, rgb):
    """One decorative shape centered on (x, y)."""
    import math
    r = size / 2
    if kind == "stars":
        pts = []
        for i in range(10):
            a = math.pi / 2 + i * math.pi / 5
            rr = r if i % 2 == 0 else r * 0.45
            pts.append((x + rr * math.cos(a), y + rr * math.sin(a)))
        polygon(p, pts, rgb)
    elif kind == "hearts":
        _curve(p, [(x, y - r * 0.9),
                   ((x - r * 1.2, y + r * 0.1), (x - r * 0.6, y + r * 1.1), (x, y + r * 0.45)),
                   ((x + r * 0.6, y + r * 1.1), (x + r * 1.2, y + r * 0.1), (x, y - r * 0.9))],
               rgb, 1, fill=True)
    elif kind == "leaves":
        _curve(p, [(x - r, y - r),
                   ((x - r * 0.2, y - r * 0.9), (x + r * 0.9, y + r * 0.2), (x + r, y + r)),
                   ((x + r * 0.2, y + r * 0.9), (x - r * 0.9, y - r * 0.2), (x - r, y - r))],
               rgb, 1, fill=True)
        p.line(x - r, y - r, x + r * 0.7, y + r * 0.7, rgb=tint(rgb, 0.55), width=0.6)
    elif kind == "sun":
        circle(p, x, y, r * 0.45, rgb)
        for i in range(8):
            a = i * math.pi / 4
            p.line(x + r * 0.62 * math.cos(a), y + r * 0.62 * math.sin(a),
                   x + r * math.cos(a), y + r * math.sin(a), rgb=rgb, width=1.2)
    elif kind == "waves":
        for k in range(3):
            yy = y - r * 0.6 + k * r * 0.6
            _curve(p, [(x - r, yy), ((x - r / 2, yy + r * 0.3), (x - r / 2, yy - r * 0.3), (x, yy)),
                       ((x + r / 2, yy + r * 0.3), (x + r / 2, yy - r * 0.3), (x + r, yy))], rgb, 1.1)
    elif kind == "dots":
        for dx, dy in ((-0.5, -0.5), (0.5, -0.5), (0, 0.4)):
            circle(p, x + dx * r, y + dy * r, r * 0.28, rgb)
    elif kind == "moons":
        circle(p, x, y, r * 0.7, rgb)
        circle(p, x + r * 0.32, y + r * 0.2, r * 0.6, S.paper or (1, 1, 1))


def _border(p, inset):
    import random
    x0, y0, x1, y1 = inset, inset, W - inset, H - inset
    rgb = tint(S.accent, 0.45)
    if S.border == "double":
        p.rect(x0, y0, x1 - x0, y1 - y0, stroke=rgb, width=1.4)
        p.rect(x0 + 5, y0 + 5, x1 - x0 - 10, y1 - y0 - 10, stroke=rgb, width=0.6)
    elif S.border in ("dashed", "stitched"):
        dash = "[6 4] 0 d" if S.border == "dashed" else "[3 3] 0 d"
        p.color(rgb, stroke=True)
        p.ops.append(f"{dash} 1 w {x0:.1f} {y0:.1f} {x1 - x0:.1f} {y1 - y0:.1f} re S [] 0 d")
    elif S.border == "hand":
        # A slightly wobbly line, like a pen-drawn frame. Seeded per page
        # count so output is repeatable.
        rnd = random.Random(len(p.ops))
        corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)]
        pts = []
        for (ax, ay), (bx, by) in zip(corners, corners[1:]):
            for i in range(12):
                t = i / 12
                pts.append((ax + (bx - ax) * t + rnd.uniform(-1.2, 1.2),
                            ay + (by - ay) * t + rnd.uniform(-1.2, 1.2)))
        polygon(p, pts, rgb, fill=False, width=1.1)


def decorate(p):
    """Background, border and corner motifs for the current style. The
    default style adds nothing."""
    if S.paper:
        p.rect(0, 0, W, H, fill=S.paper)
    if S.border != "none":
        _border(p, 16)
    if S.motif != "none":
        light = tint(S.accent, 0.35)
        for x, y, size in ((W - 30, 30, 16), (W - 52, 24, 9), (30, H - 30, 12)):
            motif_shape(p, S.motif, x, y, size, light)


def header(p, x, y, title, size):
    """A page title in the current style's header look."""
    if S.header == "banner":
        w = text_width(title, size) + size
        p.rect(x - size * 0.4, y - size * 0.32, w, size * 1.25, fill=S.accent)
        p.text(x + size * 0.1, y, title, size, rgb=S.on_accent, bold=True)
        return
    p.text(x, y, title, size, rgb=S.accent, bold=True)
    if S.header == "underline":
        p.line(x, y - size * 0.3, x + text_width(title, size), y - size * 0.3, rgb=S.accent, width=2)
    elif S.header == "swash":
        w = text_width(title, size)
        _curve(p, [(x, y - size * 0.32),
                   ((x + w * 0.35, y - size * 0.6), (x + w * 0.7, y - size * 0.05), (x + w + 10, y - size * 0.35))],
               tint(S.accent, 0.2), 1.6)
        if S.motif != "none":
            motif_shape(p, S.motif, x + w + 22, y + size * 0.3, size * 0.45, tint(S.accent, 0.3))


def write_pdf(pages, path):
    """Writes [pages] as a PDF; link targets are page indexes (0-based)."""
    objs = {}
    first_page = 5
    page_ids = [first_page + 2 * i for i in range(len(pages))]
    annot_ids = {}
    next_id = first_page + 2 * len(pages)
    for i, p in enumerate(pages):
        annot_ids[i] = list(range(next_id, next_id + len(p.links)))
        next_id += len(p.links)

    objs[1] = "<< /Type /Catalog /Pages 2 0 R >>"
    objs[2] = "<< /Type /Pages /Kids [%s] /Count %d >>" % (
        " ".join(f"{pid} 0 R" for pid in page_ids),
        len(pages),
    )
    regular, bold = ("Times-Roman", "Times-Bold") if S.serif else ("Helvetica", "Helvetica-Bold")
    objs[3] = f"<< /Type /Font /Subtype /Type1 /BaseFont /{regular} /Encoding /WinAnsiEncoding >>"
    objs[4] = f"<< /Type /Font /Subtype /Type1 /BaseFont /{bold} /Encoding /WinAnsiEncoding >>"
    for i, p in enumerate(pages):
        pid = page_ids[i]
        annots = " ".join(f"{a} 0 R" for a in annot_ids[i])
        objs[pid] = (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {p.w} {p.h}] "
            f"/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> "
            f"/Contents {pid + 1} 0 R /Annots [{annots}] >>"
        )
        stream = zlib.compress("\n".join(p.ops).encode("latin-1"), 9)
        objs[pid + 1] = (f"<< /Length {len(stream)} /Filter /FlateDecode >>\nstream\n".encode()
                         + stream + b"\nendstream")
        for aid, ((x0, y0, x1, y1), target) in zip(annot_ids[i], p.links):
            objs[aid] = (
                f"<< /Type /Annot /Subtype /Link /Rect [{x0:.1f} {y0:.1f} {x1:.1f} {y1:.1f}] "
                f"/Border [0 0 0] /Dest [{page_ids[target]} 0 R /Fit] >>"
            )

    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = {}
    for oid in sorted(objs):
        offsets[oid] = len(out)
        body = objs[oid]
        body = body if isinstance(body, bytes) else body.encode("latin-1")
        out += f"{oid} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    count = max(objs) + 1
    out += f"xref\n0 {count}\n0000000000 65535 f \n".encode()
    for oid in range(1, count):
        out += f"{offsets[oid]:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {count} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    path.write_bytes(bytes(out))


def write_preview(pdf, out):
    """Renders the first page with macOS sips, saved as a WebP preview."""
    from PIL import Image

    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "p.png"
        subprocess.run(
            ["sips", "-s", "format", "png", "-Z", "512", str(pdf), "--out", str(png)],
            check=True,
            capture_output=True,
        )
        with Image.open(png) as im:
            # Pages without a paper colour are transparent; show them on white.
            page = Image.new("RGB", im.size, (255, 255, 255))
            page.paste(im, (0, 0), im.convert("RGBA"))
            page.save(out, "WEBP", quality=88)


# The planner


# A span edition runs from October of its year to the end of the next, so
# it can be started straight away: October 2026 to December 2027.
SPAN_MONTH, SPAN_MONTHS = 10, 15


def span_title(year):
    return f"{year}-{(year + 1) % 100:02d}"


def span_name(year):
    return f"Oct {year} - Dec {year + 1}"


def planner(year, span=False):
    """The linked weekly and daily planner for [year] (or with [span], from
    October [year] to December of the next); see planner_nav."""
    import planner_nav as nav

    if span:
        book = nav.Planner(span_title(year), dt.date(year, SPAN_MONTH, 1), week_body=nav.week_boxes,
                           day_body=nav.day_plan, months=SPAN_MONTHS)
    else:
        book = nav.Planner(str(year), dt.date(year, 1, 1), week_body=nav.week_boxes, day_body=nav.day_plan)
    return book.build()


# Single pages


def essentials():
    left, right = 48, W - 48
    todo, meeting, habits = Page(), Page(), Page()

    header(todo, left, H - 72, "To-do", 30)
    todo.text(left, H - 94, "Date  ________________", 11, rgb=S.soft)
    for i in range(20):
        y = H - 140 - i * 30
        todo.rect(left, y - 3, 14, 14, stroke=S.soft, width=1)
        todo.line(left + 26, y - 4, right, y - 4)

    header(meeting, left, H - 72, "Meeting notes", 30)
    for i, label in enumerate(["Topic", "Date", "People"]):
        y = H - 112 - i * 28
        meeting.text(left, y, label, 11, rgb=S.soft, bold=True)
        meeting.line(left + 64, y - 4, right, y - 4)
    meeting.text(left, H - 214, "Notes", 12, rgb=S.accent, bold=True)
    for i in range(12):
        meeting.line(left, H - 236 - i * 26, right, H - 236 - i * 26)
    meeting.text(left, 200, "Actions", 12, rgb=S.accent, bold=True)
    for i in range(5):
        y = 176 - i * 28
        meeting.rect(left, y - 3, 12, 12, stroke=S.soft, width=1)
        meeting.line(left + 22, y - 4, right, y - 4)

    header(habits, left, H - 72, "Habit tracker", 30)
    habits.text(left, H - 94, "Month  ________________", 11, rgb=S.soft)
    days, name_w = 31, 120
    cw = (right - left - name_w) / days
    top = H - 140
    for d in range(days):
        habits.text(left + name_w + d * cw + cw / 2, top + 6, str(d + 1), 6.5, rgb=S.soft, center=True)
    for r in range(14):
        y = top - (r + 1) * 30
        habits.line(left, y, left + name_w - 6, y)
        for d in range(days):
            habits.rect(left + name_w + d * cw + 1, y + 4, cw - 2, cw - 2, stroke=S.rule, width=0.6)

    spec = {
        "mode": "pages",
        "pages": [
            {"pdfPage": 1, "title": "To-do list"},
            {"pdfPage": 2, "title": "Meeting notes"},
            {"pdfPage": 3, "title": "Habit tracker"},
        ],
    }
    return [todo, meeting, habits], spec


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "planner":
        year = int(sys.argv[2])
        span = "--span" in sys.argv
        folder = ROOT / "catalog" / (f"planner_{year}_{(year + 1) % 100:02d}" if span else f"planner_{year}")
        pages, spec = planner(year, span)
    elif len(sys.argv) == 2 and sys.argv[1] == "essentials":
        folder = ROOT / "catalog" / "essentials_pages"
        pages, spec = essentials()
    else:
        sys.exit(__doc__)
    folder.mkdir(parents=True, exist_ok=True)
    write_pdf(pages, folder / "template.pdf")
    (folder / "template.json").write_text(json.dumps(spec, indent=2) + "\n")
    write_preview(folder / "template.pdf", folder / "preview.webp")
    print(f"{folder.relative_to(ROOT)}: {len(pages)} pages")


if __name__ == "__main__":
    main()

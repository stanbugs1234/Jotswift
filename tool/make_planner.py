"""Makes Jotswift's own PDF templates, with links between pages.

  python3 tool/make_planner.py planner 2027   # catalog/planner_2027/
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
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

W, H = 612, 792  # US Letter, in points
INK = (0.12, 0.14, 0.19)
SOFT = (0.55, 0.6, 0.68)
RULE = (0.79, 0.84, 0.92)
ACCENT = (0.17, 0.29, 0.49)
TAB = (0.93, 0.95, 0.98)

# Helvetica character widths (per 1000 units), for centering and fitting.
_NARROW = set("iljtfrI.,:;'!|() ")
_WIDE = set("mwMW@%")


def text_width(s, size):
    total = 0
    for ch in s:
        total += 278 if ch in _NARROW else 889 if ch in _WIDE else 667 if ch.isupper() else 556
    return total * size / 1000


class Page:
    def __init__(self):
        self.ops = []
        self.links = []  # (rect, target page index)

    def color(self, rgb, stroke=False):
        self.ops.append("%.3f %.3f %.3f %s" % (*rgb, "RG" if stroke else "rg"))

    def line(self, x0, y0, x1, y1, rgb=RULE, width=0.8):
        self.color(rgb, stroke=True)
        self.ops.append(f"{width} w {x0:.1f} {y0:.1f} m {x1:.1f} {y1:.1f} l S")

    def rect(self, x, y, w, h, fill=None, stroke=None, width=0.8):
        if fill:
            self.color(fill)
        if stroke:
            self.color(stroke, stroke=True)
            self.ops.append(f"{width} w")
        op = "B" if fill and stroke else "f" if fill else "S"
        self.ops.append(f"{x:.1f} {y:.1f} {w:.1f} {h:.1f} re {op}")

    def text(self, x, y, s, size=11, rgb=INK, bold=False, center=False, right=False):
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
    objs[3] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
    objs[4] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>"
    for i, p in enumerate(pages):
        pid = page_ids[i]
        annots = " ".join(f"{a} 0 R" for a in annot_ids[i])
        objs[pid] = (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {W} {H}] "
            f"/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> "
            f"/Contents {pid + 1} 0 R /Annots [{annots}] >>"
        )
        stream = "\n".join(p.ops).encode("latin-1")
        objs[pid + 1] = (f"<< /Length {len(stream)} >>\nstream\n".encode() + stream + b"\nendstream")
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
            im.convert("RGB").save(out, "WEBP", quality=88)


# The planner


def planner(year):
    months = list(calendar.month_name)[1:]
    # Weeks start on Monday; the first is the week holding January 1.
    jan1 = dt.date(year, 1, 1)
    first_monday = jan1 - dt.timedelta(days=jan1.weekday())
    weeks = []
    monday = first_monday
    while monday <= dt.date(year, 12, 31):
        weeks.append(monday)
        monday += dt.timedelta(days=7)

    YEAR = 0
    month_page = {m: 1 + m for m in range(12)}
    week_page = {i: 13 + i for i in range(len(weeks))}

    def week_of(day):
        return (day - first_monday).days // 7

    pages = [Page() for _ in range(13 + len(weeks))]
    tab_x, tab_w = W - 34, 26

    def tabs(p, current_month=None):
        """Month tabs down the right edge, and a year tab on top."""
        top = H - 60
        p.rect(tab_x, top, tab_w, 30, fill=ACCENT if current_month is None and p is pages[YEAR] else TAB)
        p.text(tab_x + tab_w / 2, top + 11, str(year)[2:], 9, rgb=(1, 1, 1) if p is pages[YEAR] else ACCENT, bold=True, center=True)
        p.link(tab_x, top, tab_w, 30, YEAR)
        h = (top - 40 - 12 * 4) / 12
        for m in range(12):
            y = top - 8 - (m + 1) * (h + 4)
            on = m == current_month
            p.rect(tab_x, y, tab_w, h, fill=ACCENT if on else TAB)
            p.text(tab_x + tab_w / 2, y + h / 2 - 3.5, months[m][:3], 8, rgb=(1, 1, 1) if on else ACCENT, bold=on, center=True)
            p.link(tab_x, y, tab_w, h, month_page[m])

    left, right = 40, tab_x - 16

    # Year page: twelve small months, each linking to its page.
    p = pages[YEAR]
    p.text(left, H - 70, str(year), 40, rgb=ACCENT, bold=True)
    p.text(left, H - 92, "Weekly planner", 12, rgb=SOFT)
    cols, rows = 3, 4
    gw, gh = (right - left) / cols, (H - 130 - 50) / rows
    for m in range(12):
        cx, cy = left + (m % cols) * gw, H - 130 - (m // cols + 1) * gh
        p.rect(cx + 4, cy + 4, gw - 8, gh - 8, stroke=RULE)
        p.text(cx + 12, cy + gh - 26, months[m], 12, rgb=ACCENT, bold=True)
        cw = (gw - 24) / 7
        for i, d in enumerate("MTWTFSS"):
            p.text(cx + 12 + i * cw + cw / 2, cy + gh - 44, d, 7, rgb=SOFT, center=True)
        for r, week in enumerate(calendar.Calendar(0).monthdayscalendar(year, m + 1)):
            for i, day in enumerate(week):
                if day:
                    p.text(cx + 12 + i * cw + cw / 2, cy + gh - 58 - r * 13, str(day), 7.5, center=True)
        p.link(cx + 4, cy + 4, gw - 8, gh - 8, month_page[m])
    tabs(p)

    # Month pages: a calendar where each week row links to its week page.
    for m in range(12):
        p = pages[month_page[m]]
        p.text(left, H - 70, months[m], 32, rgb=ACCENT, bold=True)
        p.text(left, H - 92, str(year), 12, rgb=SOFT)
        p.link(left, H - 98, 60, 20, YEAR)
        grid_top, grid_left = H - 130, left + 34
        cw = (right - grid_left) / 7
        for i, d in enumerate(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]):
            p.text(grid_left + i * cw + 6, grid_top + 6, d, 9, rgb=SOFT, bold=True)
        rows_ = calendar.Calendar(0).monthdatescalendar(year, m + 1)
        rh = (grid_top - 230) / len(rows_)
        for r, week in enumerate(rows_):
            y = grid_top - (r + 1) * rh
            w = week_of(week[0])
            p.rect(left, y, 30, rh, fill=TAB)
            p.text(left + 15, y + rh / 2 - 3, f"W{w + 1}", 8, rgb=ACCENT, bold=True, center=True)
            p.link(left, y, grid_left - left + 7 * cw, rh, week_page[w])
            for i, day in enumerate(week):
                x = grid_left + i * cw
                p.rect(x, y, cw, rh, stroke=RULE)
                inside = day.month == m + 1
                p.text(x + 6, y + rh - 14, str(day.day), 10, rgb=INK if inside else RULE, bold=inside)
        p.text(left, 196, "Notes", 11, rgb=ACCENT, bold=True)
        for i in range(6):
            p.line(left, 180 - i * 26, right, 180 - i * 26)
        tabs(p, m)

    # Week pages: a box per day, and arrows to the weeks around it.
    for i, monday in enumerate(weeks):
        p = pages[week_page[i]]
        sunday = monday + dt.timedelta(days=6)
        span = f"{months[monday.month - 1][:3]} {monday.day} - {months[sunday.month - 1][:3]} {sunday.day}"
        p.text(left, H - 66, f"Week {i + 1}", 26, rgb=ACCENT, bold=True)
        p.text(left, H - 86, span, 12, rgb=SOFT)
        month = monday.month - 1 if monday.year == year else 0
        p.text(left + 180, H - 86, months[month], 12, rgb=ACCENT)
        p.link(left + 176, H - 92, 90, 20, month_page[month])
        if i > 0:
            p.text(right - 64, H - 70, "<", 18, rgb=ACCENT, bold=True)
            p.link(right - 70, H - 78, 26, 28, week_page[i - 1])
        if i < len(weeks) - 1:
            p.text(right - 20, H - 70, ">", 18, rgb=ACCENT, bold=True)
            p.link(right - 26, H - 78, 26, 28, week_page[i + 1])
        top = H - 110
        bw = (right - left - 12) / 2
        bh = (top - 40 - 3 * 12) / 4
        boxes = [monday + dt.timedelta(days=d) for d in range(7)] + [None]
        for b, day in enumerate(boxes):
            x = left + (b % 2) * (bw + 12)
            y = top - (b // 2 + 1) * bh - (b // 2) * 12
            p.rect(x, y, bw, bh, stroke=RULE)
            if day is None:
                p.text(x + 10, y + bh - 18, "Notes", 11, rgb=ACCENT, bold=True)
            else:
                p.text(x + 10, y + bh - 18, day.strftime("%A"), 11, rgb=ACCENT, bold=True)
                p.text(x + bw - 10, y + bh - 18, f"{months[day.month - 1][:3]} {day.day}", 10, rgb=SOFT, right=True)
            for k in range(1, int((bh - 30) / 22) + 1):
                p.line(x + 10, y + bh - 26 - k * 22, x + bw - 10, y + bh - 26 - k * 22)
        tabs(p, month if monday.year == year else None)

    spec = {
        "mode": "notebook",
        "sections": [
            {"title": str(year), "pages": [{"pdfPage": 1, "title": str(year)}]},
            {"title": "Months", "pages": [{"pdfPage": month_page[m] + 1, "title": months[m]} for m in range(12)]},
            {"title": "Weeks", "pages": [{"pdfPage": week_page[i] + 1, "title": f"Week {i + 1}"} for i in range(len(weeks))]},
        ],
    }
    return pages, spec


# Single pages


def essentials():
    left, right = 48, W - 48
    todo, meeting, habits = Page(), Page(), Page()

    todo.text(left, H - 72, "To-do", 30, rgb=ACCENT, bold=True)
    todo.text(left, H - 94, "Date  ________________", 11, rgb=SOFT)
    for i in range(20):
        y = H - 140 - i * 30
        todo.rect(left, y - 3, 14, 14, stroke=SOFT, width=1)
        todo.line(left + 26, y - 4, right, y - 4)

    meeting.text(left, H - 72, "Meeting notes", 30, rgb=ACCENT, bold=True)
    for i, label in enumerate(["Topic", "Date", "People"]):
        y = H - 112 - i * 28
        meeting.text(left, y, label, 11, rgb=SOFT, bold=True)
        meeting.line(left + 64, y - 4, right, y - 4)
    meeting.text(left, H - 214, "Notes", 12, rgb=ACCENT, bold=True)
    for i in range(12):
        meeting.line(left, H - 236 - i * 26, right, H - 236 - i * 26)
    meeting.text(left, 200, "Actions", 12, rgb=ACCENT, bold=True)
    for i in range(5):
        y = 176 - i * 28
        meeting.rect(left, y - 3, 12, 12, stroke=SOFT, width=1)
        meeting.line(left + 22, y - 4, right, y - 4)

    habits.text(left, H - 72, "Habit tracker", 30, rgb=ACCENT, bold=True)
    habits.text(left, H - 94, "Month  ________________", 11, rgb=SOFT)
    days, name_w = 31, 120
    cw = (right - left - name_w) / days
    top = H - 140
    for d in range(days):
        habits.text(left + name_w + d * cw + cw / 2, top + 6, str(d + 1), 6.5, rgb=SOFT, center=True)
    for r in range(14):
        y = top - (r + 1) * 30
        habits.line(left, y, left + name_w - 6, y)
        for d in range(days):
            habits.rect(left + name_w + d * cw + 1, y + 4, cw - 2, cw - 2, stroke=RULE, width=0.6)

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
        folder = ROOT / "catalog" / f"planner_{year}"
        pages, spec = planner(year)
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

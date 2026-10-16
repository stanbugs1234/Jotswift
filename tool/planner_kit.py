"""The engine behind Jotswift's bestseller-style planners (Focus, Wellness,
Life, Goals & Projects, Student, Business): see make_life_planners.py.

A Book is a year of linked pages in landscape or portrait, with the week
starting Monday or Sunday. Pages run month by month, so scrolling is
natural: each month's calendar and its extra pages, then each week page
followed by that week's days. Collections (Finance, Courses, Brain
dumps...) and Notes follow, each with its own index.

Every page has the same frame: a Home button and a trail at the top left,
arrows to the pages beside it at the top right, month tabs down the right
edge and collection tabs along the bottom. Every date on every calendar
opens its day; week rows open their week.

Every page belongs to a group, so the app's planner builder can leave out
optional groups (daily check-ins, weekly reviews, a collection...).

Pages are drawn by bodies: functions taking a Ctx, which says where to
draw (left, right, top, bottom) and what the page is about (month, week,
day or item index). planner_pages.py holds them.
"""

import calendar
import datetime as dt
import math
from dataclasses import dataclass, field

import make_planner as mp
from make_planner import Page, circle, polygon, text_width, tint

MONTHS = list(calendar.month_name)[1:]
DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
LEFT = 32
TAB_W = 30


def S():
    return mp.S


def hex_rgb(hex_):
    h = hex_.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def add_months(d, n):
    y, m = divmod(d.month - 1 + n, 12)
    return dt.date(d.year + y, m + 1, 1)


# Drawing helpers

def rrect(p, x, y, w, h, r, fill=None, stroke=None, width=0.8):
    """A rounded rectangle."""
    r = max(0, min(r, w / 2, h / 2))
    k = 0.5523 * r
    path = (f"{x + r:.1f} {y:.1f} m {x + w - r:.1f} {y:.1f} l "
            f"{x + w - r + k:.1f} {y:.1f} {x + w:.1f} {y + r - k:.1f} {x + w:.1f} {y + r:.1f} c "
            f"{x + w:.1f} {y + h - r:.1f} l "
            f"{x + w:.1f} {y + h - r + k:.1f} {x + w - r + k:.1f} {y + h:.1f} {x + w - r:.1f} {y + h:.1f} c "
            f"{x + r:.1f} {y + h:.1f} l "
            f"{x + r - k:.1f} {y + h:.1f} {x:.1f} {y + h - r + k:.1f} {x:.1f} {y + h - r:.1f} c "
            f"{x:.1f} {y + r:.1f} l "
            f"{x:.1f} {y + r - k:.1f} {x + r - k:.1f} {y:.1f} {x + r:.1f} {y:.1f} c h")
    if fill:
        p.color(fill)
    if stroke:
        p.color(stroke, stroke=True)
        p.ops.append(f"{width} w")
    p.ops.append(path + (" B" if fill and stroke else " f" if fill else " S"))


def stroke_path(p, pts, rgb, width=1.2, close=False):
    p.color(rgb, stroke=True)
    path = " ".join(f"{x:.1f} {y:.1f} {'m' if i == 0 else 'l'}" for i, (x, y) in enumerate(pts))
    p.ops.append(f"{width} w 1 J 1 j {path}{' h' if close else ''} S")


def chevron(p, x, y, size, rgb, back=False, width=1.4):
    """A > (or <) centred on (x, y)."""
    d = size / 2
    dx = -d / 2 if back else d / 2
    stroke_path(p, [(x - dx, y + d), (x + dx, y), (x - dx, y - d)], rgb, width)


def icon(p, kind, cx, cy, size, rgb):
    """A small line icon centred on (cx, cy)."""
    r = size / 2
    w = max(0.9, size / 11)
    if kind == "home":
        stroke_path(p, [(cx - r, cy), (cx, cy + r), (cx + r, cy)], rgb, w)
        stroke_path(p, [(cx - r * 0.7, cy + r * 0.1), (cx - r * 0.7, cy - r), (cx + r * 0.7, cy - r),
                        (cx + r * 0.7, cy + r * 0.1)], rgb, w)
    elif kind == "calendar":
        rrect(p, cx - r, cy - r * 0.9, size, r * 1.7, r * 0.2, stroke=rgb, width=w)
        p.line(cx - r, cy + r * 0.35, cx + r, cy + r * 0.35, rgb=rgb, width=w)
        for dx in (-0.45, 0.45):
            p.line(cx + dx * r, cy + r * 0.6, cx + dx * r, cy + r, rgb=rgb, width=w)
    elif kind == "target":
        for f in (1, 0.62, 0.25):
            circle(p, cx, cy, r * f, rgb, fill=f == 0.25, width=w)
    elif kind == "heart":
        mp._curve(p, [(cx, cy - r * 0.85),
                      ((cx - r * 1.25, cy + r * 0.05), (cx - r * 0.6, cy + r * 1.05), (cx, cy + r * 0.4)),
                      ((cx + r * 0.6, cy + r * 1.05), (cx + r * 1.25, cy + r * 0.05), (cx, cy - r * 0.85))],
                  rgb, w, close=True)
    elif kind == "star":
        pts = []
        for i in range(10):
            a = math.pi / 2 + i * math.pi / 5
            rr = r if i % 2 == 0 else r * 0.45
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        stroke_path(p, pts, rgb, w, close=True)
    elif kind == "coin":
        circle(p, cx, cy, r, rgb, fill=False, width=w)
        p.text(cx, cy - size * 0.24, "$", size * 0.68, rgb=rgb, bold=True, center=True)
    elif kind == "book":
        stroke_path(p, [(cx, cy - r * 0.8), (cx - r, cy - r * 0.55), (cx - r, cy + r * 0.8),
                        (cx, cy + r * 0.55), (cx + r, cy + r * 0.8), (cx + r, cy - r * 0.55),
                        (cx, cy - r * 0.8), (cx, cy + r * 0.55)], rgb, w)
    elif kind == "briefcase":
        rrect(p, cx - r, cy - r * 0.75, size, r * 1.35, r * 0.18, stroke=rgb, width=w)
        stroke_path(p, [(cx - r * 0.35, cy + r * 0.6), (cx - r * 0.35, cy + r * 0.9),
                        (cx + r * 0.35, cy + r * 0.9), (cx + r * 0.35, cy + r * 0.6)], rgb, w)
        p.line(cx - r, cy + r * 0.05, cx + r, cy + r * 0.05, rgb=rgb, width=w)
    elif kind == "check":
        stroke_path(p, [(cx - r * 0.8, cy), (cx - r * 0.2, cy - r * 0.6), (cx + r * 0.85, cy + r * 0.65)],
                    rgb, w * 1.3)
    elif kind == "sun":
        circle(p, cx, cy, r * 0.42, rgb, fill=False, width=w)
        for i in range(8):
            a = i * math.pi / 4
            p.line(cx + r * 0.65 * math.cos(a), cy + r * 0.65 * math.sin(a),
                   cx + r * math.cos(a), cy + r * math.sin(a), rgb=rgb, width=w)
    elif kind == "moon":
        mp._curve(p, [(cx + r * 0.2, cy + r),
                      ((cx - r * 1.1, cy + r * 0.9), (cx - r * 1.1, cy - r * 0.9), (cx + r * 0.2, cy - r)),
                      ((cx - r * 0.45, cy - r * 0.5), (cx - r * 0.45, cy + r * 0.5), (cx + r * 0.2, cy + r))],
                  rgb, w, close=True)
    elif kind == "drop":
        mp._curve(p, [(cx, cy + r),
                      ((cx - r * 0.2, cy + r * 0.5), (cx - r * 0.75, cy), (cx - r * 0.75, cy - r * 0.3)),
                      ((cx - r * 0.75, cy - r * 1.1), (cx + r * 0.75, cy - r * 1.1), (cx + r * 0.75, cy - r * 0.3)),
                      ((cx + r * 0.75, cy), (cx + r * 0.2, cy + r * 0.5), (cx, cy + r))], rgb, w, close=True)
    elif kind == "bolt":
        stroke_path(p, [(cx + r * 0.2, cy + r), (cx - r * 0.55, cy - r * 0.1), (cx + r * 0.05, cy - r * 0.1),
                        (cx - r * 0.2, cy - r), (cx + r * 0.55, cy + r * 0.15), (cx - r * 0.05, cy + r * 0.15)],
                    rgb, w, close=True)
    elif kind == "cloud":  # a brain dump
        for dx, dy, rr in ((-0.45, -0.15, 0.42), (0.1, 0.18, 0.5), (0.5, -0.15, 0.38)):
            circle(p, cx + dx * r, cy + dy * r, rr * r, rgb, fill=False, width=w)
    elif kind == "list":
        for k in range(3):
            y = cy + r * 0.6 - k * r * 0.6
            circle(p, cx - r * 0.75, y, r * 0.12, rgb)
            p.line(cx - r * 0.4, y, cx + r, y, rgb=rgb, width=w)
    elif kind == "leaf":
        mp._curve(p, [(cx - r, cy - r),
                      ((cx - r * 0.2, cy - r * 0.9), (cx + r * 0.9, cy + r * 0.2), (cx + r, cy + r)),
                      ((cx + r * 0.2, cy + r * 0.9), (cx - r * 0.9, cy - r * 0.2), (cx - r, cy - r))],
                  rgb, w, close=True)
        p.line(cx - r, cy - r, cx + r * 0.6, cy + r * 0.6, rgb=rgb, width=w * 0.8)
    elif kind == "cap":  # graduation cap
        polygon(p, [(cx - r, cy + r * 0.25), (cx, cy + r * 0.75), (cx + r, cy + r * 0.25), (cx, cy - r * 0.25)],
                rgb, fill=False, width=w)
        stroke_path(p, [(cx - r * 0.55, cy), (cx - r * 0.55, cy - r * 0.6), (cx + r * 0.55, cy - r * 0.6),
                        (cx + r * 0.55, cy)], rgb, w)
    elif kind == "chart":
        stroke_path(p, [(cx - r, cy + r), (cx - r, cy - r), (cx + r, cy - r)], rgb, w)
        stroke_path(p, [(cx - r * 0.6, cy - r * 0.3), (cx - r * 0.1, cy + r * 0.2), (cx + r * 0.25, cy - r * 0.1),
                        (cx + r * 0.85, cy + r * 0.6)], rgb, w)
    elif kind == "pencil":
        stroke_path(p, [(cx - r, cy - r), (cx - r * 0.75, cy - r * 0.25), (cx + r * 0.6, cy + r * 1.0 - r * 0.15),
                        (cx + r, cy + r * 0.45), (cx - r * 0.25, cy - r * 0.75)], rgb, w, close=True)
    elif kind == "plane":
        polygon(p, [(cx - r, cy), (cx + r, cy + r * 0.7), (cx + r * 0.2, cy - r), (cx, cy - r * 0.15)],
                rgb, fill=False, width=w)
    elif kind == "people":
        circle(p, cx - r * 0.35, cy + r * 0.35, r * 0.3, rgb, fill=False, width=w)
        circle(p, cx + r * 0.4, cy + r * 0.35, r * 0.3, rgb, fill=False, width=w)
        mp._curve(p, [(cx - r, cy - r), ((cx - r, cy - r * 0.1), (cx + r * 0.3, cy - r * 0.1), (cx + r * 0.3, cy - r))],
                  rgb, w)
        mp._curve(p, [(cx + r * 0.05, cy - r * 0.2), ((cx + r * 0.6, cy - r * 0.1), (cx + r, cy - r * 0.3), (cx + r, cy - r))],
                  rgb, w)
    elif kind == "gift":
        rrect(p, cx - r, cy - r, size, r * 1.3, r * 0.1, stroke=rgb, width=w)
        p.line(cx, cy - r, cx, cy + r * 0.3, rgb=rgb, width=w)
        p.line(cx - r, cy - r * 0.2, cx + r, cy - r * 0.2, rgb=rgb, width=w)
        circle(p, cx - r * 0.3, cy + r * 0.55, r * 0.25, rgb, fill=False, width=w)
        circle(p, cx + r * 0.3, cy + r * 0.55, r * 0.25, rgb, fill=False, width=w)
    else:  # a dot
        circle(p, cx, cy, r * 0.4, rgb)


def label(p, x, y, text, size=10, icon_kind=None):
    """A section label, in the accent colour, with an optional icon."""
    if icon_kind:
        icon(p, icon_kind, x + size * 0.55, y + size * 0.35, size * 1.1, S().accent)
        x += size * 1.6
    p.text(x, y, text, size, rgb=S().accent, bold=True)


def lines(p, x0, x1, top, bottom, gap=24):
    y = top
    while y >= bottom - 0.5:
        p.line(x0, y, x1, y)
        y -= gap


def checks(p, x0, x1, top, bottom, gap=24):
    """Checkbox lines from [top] down to [bottom]."""
    y = top
    while y >= bottom - 0.5:
        rrect(p, x0, y - 1, 10, 10, 2, stroke=S().soft, width=0.9)
        p.line(x0 + 17, y - 2, x1, y - 2)
        y -= gap


def dots(p, x0, x1, top, bottom, gap=14):
    y = top
    while y >= bottom:
        x = x0
        while x <= x1:
            p.rect(x - 0.45, y - 0.45, 0.9, 0.9, fill=S().soft)
            x += gap
        y -= gap


def card(p, x, y, w, h, title=None, icon_kind=None, fill=False):
    """A rounded box with an optional title; returns the y below the title."""
    rrect(p, x, y, w, h, 8, fill=S().tab if fill else None, stroke=S().rule, width=0.9)
    if title:
        label(p, x + 10, y + h - 18, title, 10, icon_kind)
        return y + h - 30
    return y + h - 10


def scale(p, x, y, n, size=11, labels=None):
    """[n] circles to colour in (a 1-n rating)."""
    for k in range(n):
        cx = x + k * (size * 1.6) + size / 2
        circle(p, cx, y, size / 2, S().soft, fill=False, width=0.9)
        if labels:
            p.text(cx, y - size - 3, labels[k], 6, rgb=S().soft, center=True)
    return x + n * size * 1.6


def columns(left, right, n, gap=16):
    w = (right - left - gap * (n - 1)) / n
    return [(left + k * (w + gap), left + k * (w + gap) + w) for k in range(n)]


def rows(top, bottom, weights, gap=12):
    """Splits top..bottom into rows by [weights]; returns (top, bottom) pairs."""
    total = sum(weights)
    span = top - bottom - gap * (len(weights) - 1)
    out, y = [], top
    for wgt in weights:
        h = span * wgt / total
        out.append((y, y - h))
        y -= h + gap
    return out


def shared(p, draw):
    """Runs [draw] and keeps what it drew as one block; write_pdf stores
    blocks drawn the same on many pages (tabs, a day's layout) only once."""
    start = len(p.ops)
    draw()
    ops = tuple(p.ops[start:])
    del p.ops[start:]
    if ops:
        p.ops.append(ops)


def write_pdf(pages, path):
    """make_planner.write_pdf, with shared blocks as Form XObjects."""
    import zlib

    forms = {}
    for p in pages:
        for op in p.ops:
            if isinstance(op, tuple) and op not in forms:
                forms[op] = len(forms)
    objs = {}
    first_form = 5
    first_page = first_form + len(forms)
    page_ids = [first_page + 2 * i for i in range(len(pages))]
    annot_ids = {}
    next_id = first_page + 2 * len(pages)
    for i, p in enumerate(pages):
        annot_ids[i] = list(range(next_id, next_id + len(p.links)))
        next_id += len(p.links)

    def stream(text, head=""):
        data = zlib.compress(text.encode("latin-1"), 9)
        return (f"<< {head}/Length {len(data)} /Filter /FlateDecode >>\nstream\n".encode()
                + data + b"\nendstream")

    fonts = "/Font << /F1 3 0 R /F2 4 0 R >>"
    objs[1] = "<< /Type /Catalog /Pages 2 0 R >>"
    objs[2] = "<< /Type /Pages /Kids [%s] /Count %d >>" % (" ".join(f"{pid} 0 R" for pid in page_ids), len(pages))
    regular, bold = ("Times-Roman", "Times-Bold") if mp.S.serif else ("Helvetica", "Helvetica-Bold")
    objs[3] = f"<< /Type /Font /Subtype /Type1 /BaseFont /{regular} /Encoding /WinAnsiEncoding >>"
    objs[4] = f"<< /Type /Font /Subtype /Type1 /BaseFont /{bold} /Encoding /WinAnsiEncoding >>"
    w, h = (pages[0].w, pages[0].h) if pages else (mp.W, mp.H)
    for ops, k in forms.items():
        objs[first_form + k] = stream("\n".join(ops),
                                      f"/Type /XObject /Subtype /Form /BBox [-20 -20 {w + 20} {h + 20}] "
                                      f"/Resources << {fonts} >> ")
    xobjects = " ".join(f"/X{k} {first_form + k} 0 R" for k in forms.values())
    for i, p in enumerate(pages):
        pid = page_ids[i]
        annots = " ".join(f"{a} 0 R" for a in annot_ids[i])
        used = sorted({forms[op] for op in p.ops if isinstance(op, tuple)})
        xo = f" /XObject << {' '.join(f'/X{k} {first_form + k} 0 R' for k in used)} >>" if used else ""
        objs[pid] = (f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {p.w} {p.h}] "
                     f"/Resources << {fonts}{xo} >> /Contents {pid + 1} 0 R /Annots [{annots}] >>")
        body = "\n".join(f"/X{forms[op]} Do" if isinstance(op, tuple) else op for op in p.ops)
        objs[pid + 1] = stream(body)
        for aid, ((x0, y0, x1, y1), target) in zip(annot_ids[i], p.links):
            objs[aid] = (f"<< /Type /Annot /Subtype /Link /Rect [{x0:.1f} {y0:.1f} {x1:.1f} {y1:.1f}] "
                         f"/Border [0 0 0] /Dest [{page_ids[target]} 0 R /Fit] >>")
    del xobjects

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


# The book

@dataclass
class Kind:
    """A kind of page under a month, week or day: [name] shows on its chip
    and in its title; [group] is what the builder can leave out."""
    name: str
    draw: object
    group: str


@dataclass
class Collection:
    """A section with an index page and its [pages]: (name, body) pairs."""
    key: str
    title: str
    icon: str
    group: str
    pages: list
    blurb: str = ""
    index: int = None
    page_ids: list = field(default_factory=list)


@dataclass
class Group:
    id: str
    title: str
    optional: bool = True
    on: bool = True


@dataclass
class Ctx:
    """Where a body draws and what about."""
    book: object
    p: Page
    left: float
    right: float
    top: float
    bottom: float
    m: int = None  # month index
    w: int = None  # week index
    d: int = None  # day index
    k: int = None  # item index within a collection

    @property
    def landscape(self):
        return mp.W > mp.H


@dataclass
class Rec:
    section: str
    title: str
    group: str
    draw: object
    first: dt.date = None
    last: dt.date = None


class Book:
    """A year of linked pages.

    [start]: the first day (dated), or None for an undated book.
    [week_start]: 0 for Monday, 6 for Sunday.
    [front]: (name, icon, body, group) pages after the year page.
    [month_kinds], [week_kinds], [day_kinds]: the pages of each month, week
    and day; the first of each is the main one (calendar, week, day).
    [collections]: Collection sections after the months.
    [groups]: Group entries; every group a page uses must be listed.
    """

    def __init__(self, title, subtitle, start, *, week_start=0, front=(), month_kinds, week_kinds,
                 day_kinds, collections=(), groups, hint="", months=12):
        self.title, self.subtitle, self.start = title, subtitle, start
        self.dated = start is not None
        # How many months: 12, or more for books like Oct 2026 - Dec 2027.
        self.n = months if self.dated else 12
        self.week_start = week_start
        self.front = list(front)
        self.month_kinds, self.week_kinds, self.day_kinds = month_kinds, week_kinds, day_kinds
        self.collections = list(collections)
        self.groups = list(groups)
        self.hint = hint
        known = {g.id for g in self.groups}
        used = {k.group for k in [*month_kinds, *week_kinds, *day_kinds]}
        used |= {c.group for c in self.collections} | {f[3] for f in self.front}
        missing = used - known - {"start", "months"}
        assert not missing, f"groups not listed: {missing}"

        if self.dated:
            self.months = [add_months(start, i) for i in range(self.n)]
            end = add_months(start, self.n)
            self.end = end - dt.timedelta(days=1)
            self.days = [start + dt.timedelta(days=i) for i in range((end - start).days)]
            first = start - dt.timedelta(days=(start.weekday() - week_start) % 7)
            self.weeks = []
            while first < end:
                self.weeks.append(first)
                first += dt.timedelta(days=7)
            self.day_index = {d: i for i, d in enumerate(self.days)}
        else:
            self.months = list(range(12))
            self.days = [(m, n) for m in range(12) for n in range(1, 32)]
            self.weeks = [(m, r) for m in range(12) for r in range(5)]
        self._plan()

    # Where things are

    def _plan(self):
        recs = self.recs = []

        def add(section, title, group, draw, first=None, last=None):
            recs.append(Rec(section, title, group, draw, first, last))
            return len(recs) - 1

        self.home = add("Start", "Home", "start", self.draw_home)
        self.year_page = add("Start", self.year_name(), "start", self.draw_year,
                             *((self.start, self.end) if self.dated else ()))
        self.front_pages = [add("Start", name, group, lambda p, k=k: self.draw_front(p, k))
                            for k, (name, _, _, group) in enumerate(self.front)]
        self.month_page = [[None] * len(self.month_kinds) for _ in range(self.n)]
        self.week_page = [[None] * len(self.week_kinds) for _ in self.weeks]
        self.day_page = [[None] * len(self.day_kinds) for _ in self.days]
        for m in range(self.n):
            section = self.month_name(m)
            for s, kind in enumerate(self.month_kinds):
                period = self.month_period(m) if s == 0 else ()
                title = self.month_name(m) if s == 0 else f"{self.month_name(m, True)} {kind.name.lower()}"
                self.month_page[m][s] = add(section, title, kind.group if s else "months",
                                            lambda p, m=m, s=s: self.draw_month_kind(p, m, s), *period)
            for d in self.days_of_month(m):
                w = self.week_of(d)
                if w is not None and self.week_page[w][0] is None:
                    for s, kind in enumerate(self.week_kinds):
                        period = self.week_period(w) if s == 0 else ()
                        title = self.week_name(w) if s == 0 else f"{self.week_name(w)} {kind.name.lower()}"
                        self.week_page[w][s] = add(section, title, kind.group,
                                                   lambda p, w=w, s=s: self.draw_week_kind(p, w, s), *period)
                for s, kind in enumerate(self.day_kinds):
                    period = (self.days[d],) if self.dated and s == 0 else ()
                    title = self.day_title(d) if s == 0 else f"{self.day_title(d)} {kind.name.lower()}"
                    self.day_page[d][s] = add(section, title, kind.group,
                                              lambda p, d=d, s=s: self.draw_day_kind(p, d, s), *period)
        for c in self.collections:
            c.index = add(c.title, c.title, c.group, lambda p, c=c: self.draw_collection_index(p, c))
            c.page_ids = [add(c.title, name, c.group, lambda p, c=c, k=k: self.draw_collection_page(p, c, k))
                          for k, (name, _) in enumerate(c.pages)]

    def days_of_month(self, m):
        if self.dated:
            first = self.months[m]
            last = add_months(first, 1)
            return [self.day_index[first + dt.timedelta(days=i)] for i in range((last - first).days)
                    if first + dt.timedelta(days=i) in self.day_index]
        return list(range(m * 31, m * 31 + 31))

    def week_of(self, d):
        """The week holding day index [d]."""
        if self.dated:
            i = (self.days[d] - self.weeks[0]).days // 7
            return i if 0 <= i < len(self.weeks) else None
        m, n = self.days[d]
        return m * 5 + (n - 1) // 7

    def week_dates(self, w):
        """The seven (dated) days of week [w], or day indexes for undated."""
        if self.dated:
            return [self.weeks[w] + dt.timedelta(days=k) for k in range(7)]
        m, r = self.weeks[w]
        return [m * 31 + r * 7 + k for k in range(7) if r * 7 + k < 31]

    def week_day_pages(self, w):
        """(label, sub, page or None) for each day of week [w]."""
        out = []
        if self.dated:
            for day in self.week_dates(w):
                i = self.day_index.get(day)
                out.append((DAY_NAMES[day.weekday()], f"{MONTHS[day.month - 1][:3]} {day.day}",
                            None if i is None else self.day_page[i][0]))
        else:
            days = self.week_dates(w)
            for k in range(7):
                out.append((self.weekday_names()[k], "", self.day_page[days[k]][0] if k < len(days) else None))
        return out

    def weekday_names(self):
        return DAY_NAMES[self.week_start:] + DAY_NAMES[:self.week_start]

    def month_of_week(self, w):
        if self.dated:
            for day in self.week_dates(w):
                i = self.day_index.get(day)
                if i is not None:
                    return self.month_of_day(i)
            return self.n - 1
        return self.weeks[w][0]

    def month_of_day(self, d):
        if self.dated:
            day = self.days[d]
            return (day.year - self.start.year) * 12 + day.month - self.start.month
        return self.days[d][0]

    def link_date(self, p, x, y, w, h, day):
        """Links the area to [day]'s page (a date, or a day index)."""
        i = self.day_index.get(day) if self.dated and isinstance(day, dt.date) else day
        if i is None or isinstance(i, dt.date):
            return False
        p.link(x, y, w, h, self.day_page[i][0])
        return True

    # Names and periods

    def year_name(self):
        if not self.dated:
            return "Year"
        if self.start.year == self.end.year:
            return str(self.start.year)
        return f"{self.start.year}-{str(self.end.year)[2:]}"

    def month_name(self, m, short=False):
        """January, or Jan; with the year (Dec 26, December 2026) when the
        book has that month twice."""
        if not self.dated:
            return f"M{m + 1}" if short else f"Month {m + 1}"
        first = self.months[m]
        name = MONTHS[first.month - 1]
        twice = sum(1 for d in self.months if d.month == first.month) > 1
        if short:
            return f"{name[:3]} {str(first.year)[2:]}" if twice else name[:3]
        return f"{name} {first.year}" if twice else name

    def month_title(self, m):
        if not self.dated:
            return f"Month {m + 1}"
        return f"{MONTHS[self.months[m].month - 1]} {self.months[m].year}"

    def month_period(self, m):
        if not self.dated:
            return ()
        first = self.months[m]
        return first, add_months(first, 1) - dt.timedelta(days=1)

    def week_period(self, w):
        if not self.dated:
            return ()
        return self.weeks[w], self.weeks[w] + dt.timedelta(days=6)

    def week_name(self, w):
        return f"Week {w + 1}"

    def week_range(self, w):
        if not self.dated:
            return "Week of  ______________"
        a, b = self.weeks[w], self.weeks[w] + dt.timedelta(days=6)
        return f"{MONTHS[a.month - 1][:3]} {a.day} - {MONTHS[b.month - 1][:3]} {b.day}, {b.year}"

    def day_title(self, d):
        if self.dated:
            day = self.days[d]
            return f"{MONTHS[day.month - 1][:3]} {day.day}"
        m, n = self.days[d]
        return f"M{m + 1} day {n}"

    def day_crumb(self, d):
        if self.dated:
            day = self.days[d]
            return f"{DAY_NAMES[day.weekday()][:3]} {day.day}"
        return f"Day {self.days[d][1]}"

    # The frame on every page

    @property
    def right(self):
        return mp.W - TAB_W - 16

    def frame(self, p, crumbs, tab=None, prev=None, next_=None, bottom_tab=None):
        """Home button and trail at the top, arrows, month tabs on the right
        and collection tabs along the bottom. [crumbs]: (label, page) after
        Home; the last is this page."""
        H = mp.H
        rrect(p, LEFT, H - 44, 26, 26, 7, fill=S().accent)
        icon(p, "home", LEFT + 13, H - 31, 13, S().on_accent)
        p.link(LEFT - 4, H - 48, 34, 34, self.home)
        x, y = LEFT + 36, H - 35
        for k, (name, target) in enumerate(crumbs):
            if k:
                chevron(p, x + 2, y + 3, 6, S().soft, width=1)
                x += 9
            last = k == len(crumbs) - 1
            p.text(x, y, name, 9.5, rgb=S().ink if last else S().accent, bold=last)
            w = text_width(name, 9.5)
            if not last:
                p.link(x - 3, y - 10, w + 6, 26, target)
            x += w + 5
        r = self.right
        for page, back, cx in ((prev, True, r - 44), (next_, False, r - 12)):
            if page is None:
                continue
            rrect(p, cx - 13, H - 44, 26, 26, 7, fill=S().tab)
            chevron(p, cx, H - 31, 10, S().accent, back=back, width=1.6)
            p.link(cx - 15, H - 48, 30, 34, page)
        shared(p, lambda: self.month_tabs(p, tab))
        shared(p, lambda: self.bottom_tabs(p, bottom_tab))

    def month_tabs(self, p, current):
        entries = [(self.year_name() if self.dated and len(self.year_name()) <= 4 else "Year",
                    self.year_page, "year")]
        entries += [(self.month_name(m, short=True), self.month_page[m][0], m) for m in range(self.n)]
        x = mp.W - TAB_W - 4
        top, bottom, gap = mp.H - 18, 34, 3
        h = (top - bottom - gap * (len(entries) - 1)) / len(entries)
        for k, (name, target, key) in enumerate(entries):
            y = top - (k + 1) * h - k * gap
            on = key == current
            rrect(p, x, y, TAB_W + 12, h, 6, fill=S().accent if on else S().tab)
            ink = S().on_accent if on else S().accent
            if " " in name:  # Dec 26: the year small, under the month
                mon, yy = name.split(" ")
                p.text(x + TAB_W / 2, y + h / 2 + 0.5, mon, 8, rgb=ink, bold=True, center=True)
                p.text(x + TAB_W / 2, y + h / 2 - 8, f"'{yy}", 6.5, rgb=ink, center=True)
            else:
                size = 7.5 if len(name) > 3 else 8.5
                p.text(x + TAB_W / 2, y + h / 2 - size * 0.35, name, size, rgb=ink, bold=True, center=True)
            p.link(x, y, TAB_W + 4, h, target)

    def bottom_tabs(self, p, current):
        if not self.collections:
            return
        n = len(self.collections)
        gap = 4
        w = min(118, (self.right - LEFT - gap * (n - 1)) / n)
        x = LEFT
        for c in self.collections:
            on = c.key == current
            rrect(p, x, -8, w, 30, 6, fill=S().accent if on else S().tab)
            ink = S().on_accent if on else S().accent
            name = c.title
            size = 8
            while text_width(name, size) > w - 26 and size > 6:
                size -= 0.5
            icon(p, c.icon, x + 11, 11, 9, ink)
            p.text(x + 20, 8, name, size, rgb=ink, bold=True)
            p.link(x, 0, w, 24, c.index)
            x += w + gap

    def heading(self, p, text, sub=None, size=24):
        mp.header(p, LEFT, mp.H - 80, text, size)
        if sub:
            p.text(LEFT, mp.H - 98, sub, 10, rgb=S().soft)

    def chips(self, p, names, pages, current, title=""):
        """Linked chips at the top right, for the pages of one month, week
        or day; smaller when they'd run into the page's [title]."""
        if len(names) < 2:
            return
        after = LEFT + text_width(title, 24) + 14
        for size, pad, least, gap in ((8.5, 18, 46, 4), (7.5, 12, 36, 3), (6.5, 8, 28, 2)):
            widths = [max(least, text_width(n, size) + pad) for n in names]
            x = self.right - sum(widths) - gap * (len(names) - 1)
            if x >= after:
                break
        y = mp.H - 88
        for k, (name, page, w) in enumerate(zip(names, pages, widths)):
            on = k == current
            rrect(p, x, y, w, 22, 11, fill=S().accent if on else S().tab)
            p.text(x + w / 2, y + 7.5, name, size, rgb=S().on_accent if on else S().accent, bold=True,
                   center=True)
            if not on:
                p.link(x, y, w, 22, page)
            x += w + gap

    def ctx(self, p, **about):
        return Ctx(self, p, LEFT, self.right, mp.H - 112, 36, **about)

    def crumbs_month(self, m):
        return [(self.year_name(), self.year_page), (self.month_name(m), self.month_page[m][0])]

    # Calendars

    def month_weeks(self, m):
        """Rows of 7 cells for month [m]: dates (dated) or day numbers
        (undated, 1-31 in five rows)."""
        if self.dated:
            first = self.months[m]
            return calendar.Calendar(self.week_start).monthdatescalendar(first.year, first.month)
        return [[r * 7 + k + 1 for k in range(7)] for r in range(5)]

    def cell_day(self, m, cell):
        """The day index for a calendar cell of month [m], or None."""
        if self.dated:
            if cell.month != self.months[m].month:
                return None
            return self.day_index.get(cell)
        return m * 31 + cell - 1 if cell <= 31 else None

    def row_week(self, m, r, row):
        if self.dated:
            for day in row:
                i = self.day_index.get(day)
                if i is not None:
                    return self.week_of(i)
            return None
        return m * 5 + r

    def mini_month(self, p, m, x, top, w, row_h, size, today=None, week_links=False, title=True):
        """Month [m] as a small grid whose dates open their days. Returns the
        bottom."""
        if title:
            p.text(x, top, self.month_name(m), size + 1, rgb=S().accent, bold=True)
            p.link(x - 2, top - 4, w * 0.6, size + 8, self.month_page[m][0])
            top -= size + 6
        cols = 8 if week_links else 7
        cw = w / cols
        x0 = x + (cw if week_links else 0)
        if self.dated:
            for k, name in enumerate(self.weekday_names()):
                p.text(x0 + k * cw + cw / 2, top, name[0], size - 1, rgb=S().soft, center=True)
        y = top
        for r, row in enumerate(self.month_weeks(m)):
            y = top - (r + 1) * row_h
            if week_links:
                wi = self.row_week(m, r, row)
                if wi is not None:
                    p.text(x + cw / 2, y, f"W{wi + 1}", size - 1.5, rgb=S().accent, bold=True, center=True)
                    p.link(x, y - row_h * 0.3, cw, row_h, self.week_page[wi][0])
            for k, cell in enumerate(row):
                i = self.cell_day(m, cell)
                if i is None:
                    continue
                n = cell.day if self.dated else cell
                cx = x0 + k * cw + cw / 2
                if i == today:
                    circle(p, cx, y + size * 0.33, size * 0.85, S().accent)
                    p.text(cx, y, str(n), size, rgb=S().on_accent, bold=True, center=True)
                else:
                    p.text(cx, y, str(n), size, center=True)
                p.link(cx - cw / 2, y - row_h * 0.3, cw, row_h, self.day_page[i][0])
        return y - row_h * 0.3

    # Pages

    def draw_home(self, p):
        H = mp.H
        r = self.right
        rrect(p, LEFT, H - 120, r - LEFT, 96, 14, fill=S().accent)
        p.text(LEFT + 22, H - 70, self.title, 30, rgb=S().on_accent, bold=True)
        p.text(LEFT + 22, H - 94, self.subtitle, 12, rgb=tint(S().on_accent, 0.0))
        if self.dated:
            p.text(r - 22, H - 70, self.year_name(), 30, rgb=S().on_accent, bold=True, right=True)
        y = H - 142
        tiles = [("Year", "calendar", self.year_page)]
        tiles += [(name, ic, page) for (name, ic, _, _), page in zip(self.front, self.front_pages)]
        tiles += [(c.title, c.icon, c.index) for c in self.collections]
        landscape = mp.W > mp.H
        per_row = 6 if landscape else 4
        th = 50 if landscape else 62
        y = self.tile_grid(p, y, "Start here", tiles, per_row, th, icons=True)
        months = [(self.month_name(m), None, self.month_page[m][0]) for m in range(self.n)]
        y = self.tile_grid(p, y, "Months", months, 6 if landscape else 4, 30 if landscape else 38)
        weeks = [(str(w + 1), None, pages[0]) for w, pages in enumerate(self.week_page)]
        per_row = 20 if landscape else 14
        th = min(26, (y - 64 - 8 * ((len(weeks) + per_row - 1) // per_row)) / ((len(weeks) + per_row - 1) // per_row))
        if th >= 16:
            self.tile_grid(p, y, "Weeks", weeks, per_row, th)
        hint = self.hint or "Tap any date, tab or tile with your finger to go there. The Pencil always writes."
        p.text(LEFT, 44, hint, 9, rgb=S().soft)
        p.text(LEFT, 32, "Tap Today at the top of the screen to open today's page.", 9, rgb=S().soft)
        self.month_tabs(p, None)
        self.bottom_tabs(p, None)

    def tile_grid(self, p, y, heading, items, per_row, h, icons=False):
        label(p, LEFT, y, heading, 11)
        y -= 10
        gap = 8
        w = (self.right - LEFT - gap * (per_row - 1)) / per_row
        for k, (name, ic, target) in enumerate(items):
            r, c = divmod(k, per_row)
            x, ty = LEFT + c * (w + gap), y - (r + 1) * h - r * gap
            rrect(p, x, ty, w, h, 9, fill=S().tab)
            size = 10.5
            while text_width(name, size) > w - (30 if icons and ic else 12) and size > 7:
                size -= 0.5
            if icons and ic:
                icon(p, ic, x + w / 2, ty + h * 0.62, min(16, h * 0.32), S().accent)
                p.text(x + w / 2, ty + h * 0.2, name, size, rgb=S().accent, bold=True, center=True)
            else:
                p.text(x + w / 2, ty + h / 2 - size * 0.35, name, size, rgb=S().accent, bold=True, center=True)
            p.link(x, ty, w, h, target)
        n = (len(items) + per_row - 1) // per_row
        return y - n * (h + gap) - 22

    def draw_year(self, p):
        self.heading(p, self.year_name() if self.dated else "Year at a glance",
                   "Tap a month, a week number or any date.")
        landscape = mp.W > mp.H
        cols = (4 if self.n <= 12 else 5) if landscape else 3
        n_rows = -(-self.n // cols)
        top, bottom = mp.H - 108, 36
        gw, gh = (self.right - LEFT) / cols, (top - bottom) / n_rows
        for m in range(self.n):
            cx, cy = LEFT + (m % cols) * gw, top - (m // cols + 1) * gh
            rrect(p, cx + 4, cy + 4, gw - 8, gh - 8, 8, stroke=S().rule)
            self.mini_month(p, m, cx + 12, cy + gh - 20, gw - 24, min(15, (gh - 44) / 6.4), 7.5,
                            week_links=True)
        self.frame(p, [(self.year_name(), self.year_page)], "year")

    def draw_front(self, p, k):
        name, _, body, _ = self.front[k]
        self.heading(p, name)
        body(self.ctx(p, k=k))
        pages = self.front_pages
        self.frame(p, [(name, pages[k])], "year",
                   prev=pages[k - 1] if k else self.year_page,
                   next_=pages[k + 1] if k + 1 < len(pages) else None)

    def draw_month_kind(self, p, m, s):
        kind = self.month_kinds[s]
        title = self.month_title(m) if s == 0 else f"{self.month_name(m)} {kind.name.lower()}"
        self.heading(p, title)
        self.chips(p, [k.name for k in self.month_kinds], self.month_page[m], s, title)
        shared(p, lambda: kind.draw(self.ctx(p, m=m)))
        crumbs = self.crumbs_month(m)
        if s:
            crumbs.append((kind.name, self.month_page[m][s]))
        self.frame(p, crumbs, m,
                   prev=self.month_page[m - 1][s] if m else None,
                   next_=self.month_page[m + 1][s] if m < self.n - 1 else None)

    def draw_week_kind(self, p, w, s):
        kind = self.week_kinds[s]
        m = self.month_of_week(w)
        name = self.week_name(w)
        self.heading(p, name if s == 0 else f"{name} {kind.name.lower()}", self.week_range(w))
        self.chips(p, [k.name for k in self.week_kinds], self.week_page[w], s)
        kind.draw(self.ctx(p, m=m, w=w))
        crumbs = self.crumbs_month(m) + [(name, self.week_page[w][0])]
        if s:
            crumbs.append((kind.name, self.week_page[w][s]))
        self.frame(p, crumbs, m,
                   prev=self.week_page[w - 1][s] if w else None,
                   next_=self.week_page[w + 1][s] if w + 1 < len(self.weeks) else None)

    def draw_day_kind(self, p, d, s):
        kind = self.day_kinds[s]
        m = self.month_of_day(d)
        if self.dated:
            day = self.days[d]
            title, sub = DAY_NAMES[day.weekday()], f"{MONTHS[day.month - 1]} {day.day}, {day.year}"
        else:
            title, sub = f"Day {self.days[d][1]}", "Date  ______________"
        if s:
            title = f"{title} · {kind.name}"
        self.heading(p, title, sub)
        self.chips(p, [k.name for k in self.day_kinds], self.day_page[d], s)
        shared(p, lambda: kind.draw(self.ctx(p, m=m, d=d, w=self.week_of(d))))
        crumbs = self.crumbs_month(m)
        w = self.week_of(d)
        if w is not None:
            crumbs.append((self.week_name(w), self.week_page[w][0]))
        crumbs.append((self.day_crumb(d), self.day_page[d][0]))
        if s:
            crumbs.append((kind.name, self.day_page[d][s]))
        self.frame(p, crumbs, m,
                   prev=self.day_page[d - 1][s] if d else None,
                   next_=self.day_page[d + 1][s] if d + 1 < len(self.days) else None)

    def draw_collection_index(self, p, c):
        self.heading(p, c.title, c.blurb or "Tap a line to open its page.")
        top, bottom = mp.H - 112, 40
        n = len(c.pages)
        landscape = mp.W > mp.H
        cols = 2 if n > (10 if landscape else 16) else 1
        per = (n + cols - 1) // cols
        rh = min(40, (top - bottom) / per)
        for k, (name, _) in enumerate(c.pages):
            col, r = divmod(k, per)
            x0, x1 = columns(LEFT, self.right, cols, 24)[col]
            y = top - (r + 1) * rh
            p.text(x0, y + 8, f"{k + 1}", 10, rgb=S().accent, bold=True)
            p.text(x0 + 24, y + 8, name, 11)
            chevron(p, x1 - 6, y + 11, 8, S().accent)
            p.line(x0 + 20, y + 3, x1, y + 3)
            p.link(x0, y, x1 - x0, rh, c.page_ids[k])
        self.frame(p, [(c.title, c.index)], None, bottom_tab=c.key)

    def draw_collection_page(self, p, c, k):
        name, body = c.pages[k]
        self.heading(p, name)
        shared(p, lambda: body(self.ctx(p, k=k)))
        ids = c.page_ids
        self.frame(p, [(c.title, c.index), (name, ids[k])], None,
                   prev=ids[k - 1] if k else None, next_=ids[k + 1] if k + 1 < len(ids) else None,
                   bottom_tab=c.key)

    # Output

    def build(self):
        pages = []
        for rec in self.recs:
            p = Page()
            rec.draw(p)
            pages.append(p)
        return pages, self.spec()

    def spec(self):
        sections = []
        for i, rec in enumerate(self.recs):
            if not sections or sections[-1]["title"] != rec.section:
                sections.append({"title": rec.section, "pages": []})
            e = {"pdfPage": i + 1, "title": rec.title}
            if rec.group != "start" and rec.group != "months":
                e["group"] = rec.group
            if rec.first is not None:
                e.update({"from": rec.first.isoformat(), "to": (rec.last or rec.first).isoformat()})
            sections[-1]["pages"].append(e)
        return {"mode": "notebook", "sections": sections}

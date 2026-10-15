"""Makes Jotswift's linked diaries and planners: a year page, month pages
and a page per day or per week, with month tabs and next/previous arrows.

  python3 tool/make_diary.py diary_classic 2027      # catalog/diary_classic_2027/
  python3 tool/make_diary.py all 2027                # every book below
  python3 tool/make_diary.py --list

Books (see BOOKS): Classic, Modern and Landscape daily/weekly diaries,
three tabbed diaries in different colours, Academic and Teacher planners
(July to June) and undated weekly and daily planners. Dated books need a
year; academic ones start in July of that year.

Writes template.pdf, template.json, preview.webp and listing.json.
Re-running keeps each item's version; raise it by hand when pages change.
Needs Pillow, and macOS `sips` for the preview.
"""

import calendar
import datetime as dt
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import make_planner as mp  # noqa: E402
from make_planner import Page, Style, circle, header, tint  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
MONTHS = list(calendar.month_name)[1:]
DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def rgb(hex_):
    h = hex_.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def S():
    return mp.S


# Styles. Tab colours, when set, give each month its own tab colour.

CLASSIC = Style(ink=rgb("#2B2622"), soft=rgb("#8C8176"), rule=rgb("#DCD3C4"), accent=rgb("#6B3E2E"),
                tab=rgb("#F1EADF"), paper=rgb("#FBF8F2"), border="double", header="underline", serif=True)
MODERN = Style(ink=rgb("#1E2328"), soft=rgb("#7C8790"), rule=rgb("#DDE3E8"), accent=rgb("#1F6F78"),
               tab=rgb("#E7F1F2"), header="banner")
LANDSCAPE = Style(ink=rgb("#23262B"), soft=rgb("#858B94"), rule=rgb("#DADFE6"), accent=rgb("#3A4E7A"),
                  tab=rgb("#ECEFF5"))
LAVENDER = Style(ink=rgb("#2E2A3A"), soft=rgb("#8D86A3"), rule=rgb("#E2DCF0"), accent=rgb("#6A5A9C"),
                 tab=rgb("#F0ECF8"), paper=rgb("#FDFCFF"), header="swash", motif="stars")
LINEN = Style(ink=rgb("#33291F"), soft=rgb("#957F68"), rule=rgb("#E6D9C6"), accent=rgb("#8A5A33"),
              tab=rgb("#F3EBDD"), paper=rgb("#FBF6EE"), border="stitched", header="underline", serif=True)
SORBET = Style(ink=rgb("#3A2B2E"), soft=rgb("#A08588"), rule=rgb("#F2DCDD"), accent=rgb("#C2566A"),
               tab=rgb("#FBEDEE"), paper=rgb("#FFFCFB"), header="banner", motif="hearts")
ACADEMIC = Style(ink=rgb("#1F2433"), soft=rgb("#7F879B"), rule=rgb("#D9DEEA"), accent=rgb("#2F4B8C"),
                 tab=rgb("#E9EEF8"), header="underline")
TEACHER = Style(ink=rgb("#26302A"), soft=rgb("#7E8C82"), rule=rgb("#D7E2DA"), accent=rgb("#3D7A55"),
                tab=rgb("#E8F2EB"), header="banner")
UNDATED = Style(ink=rgb("#24272B"), soft=rgb("#848A91"), rule=rgb("#DDE0E4"), accent=rgb("#4E5A66"),
                tab=rgb("#EEF0F2"))

RAINBOW = {
    "lavender": ["#B9A7E0", "#A7B7E8", "#9CCBE0", "#A2D6C4", "#BFDBA2", "#E2D99A",
                 "#EFC79C", "#EEB0A6", "#E7A6C1", "#D2A6DC", "#B9A7E0", "#A7B7E8"],
    "linen": ["#C9A27E", "#B88E6A", "#A98263", "#9C8F6B", "#8F9873", "#86977F",
              "#8A8E8B", "#998478", "#AA7F6E", "#B98A72", "#C6987A", "#D2A784"],
    "sorbet": ["#F4A6A6", "#F6BE9A", "#F5D58E", "#C9E3A0", "#A6DCC6", "#9FD0E8",
               "#AFB8EC", "#C8AEEA", "#E6A8DA", "#F2A6BE", "#F4A6A6", "#F6BE9A"],
}


class Book:
    """A dated or undated book. [unit] is "day" or "week". Pages: the year
    page, any [front] pages, 12 month pages, then the days or weeks."""

    def __init__(self, title, start, unit, dated=True, front=(), tabs=None, landscape=False):
        self.title, self.start, self.unit, self.dated = title, start, unit, dated
        self.front, self.tab_colors, self.landscape = list(front), tabs, landscape
        self.months = [self._add_months(start, i) for i in range(12)]
        if unit == "day":
            if dated:
                end = self._add_months(start, 12)
                self.periods = [start + dt.timedelta(days=i) for i in range((end - start).days)]
            else:
                self.periods = [(m, d) for m in range(12) for d in range(1, 32)]
        else:
            if dated:
                first = start - dt.timedelta(days=start.weekday())
                end = self._add_months(start, 12)
                self.periods = []
                monday = first
                while monday < end:
                    self.periods.append(monday)
                    monday += dt.timedelta(days=7)
            else:
                self.periods = list(range(52))
        self.year_page = 0
        self.front_pages = list(range(1, 1 + len(self.front)))
        first_month = 1 + len(self.front)
        self.month_page = {m: first_month + m for m in range(12)}
        first_period = first_month + 12
        self.period_page = {i: first_period + i for i in range(len(self.periods))}

    @staticmethod
    def _add_months(d, n):
        y, m = divmod(d.month - 1 + n, 12)
        return dt.date(d.year + y, m + 1, 1)

    # Which month each period belongs to (for tabs and back links).
    def month_of(self, i):
        p = self.periods[i]
        if not self.dated:
            return p[0] if self.unit == "day" else min(11, i * 12 // 52)
        day = p if self.unit == "day" else max(p, self.start)
        for m, first in enumerate(self.months):
            if first.year == day.year and first.month == day.month:
                return m
        return 11

    def period_of(self, day):
        """The page index for a date (dated books)."""
        if self.unit == "day":
            return self.period_page[(day - self.start).days]
        first = self.periods[0]
        return self.period_page[min(len(self.periods) - 1, (day - first).days // 7)]

    # Drawing helpers

    @property
    def right(self):
        return mp.W - 52

    def tabs(self, p, current=None):
        """The year tab and twelve month tabs down the right edge."""
        x, w = mp.W - 34, 26
        top = mp.H - 56
        on_year = current == "year"
        p.rect(x, top, w, 30, fill=S().accent if on_year else S().tab)
        label = str(self.start.year)[2:] if self.dated else "Yr"
        p.text(x + w / 2, top + 11, label, 9, rgb=S().on_accent if on_year else S().accent, bold=True, center=True)
        p.link(x, top, w, 30, self.year_page)
        h = (top - 36 - 12 * 3) / 12
        for m in range(12):
            y = top - 6 - (m + 1) * (h + 3)
            on = m == current
            color = rgb(self.tab_colors[m]) if self.tab_colors else None
            fill = S().accent if on else (tint(color, 0.35) if color else S().tab)
            p.rect(x, y, w, h, fill=fill)
            name = MONTHS[self.months[m].month - 1][:3] if self.dated else str(m + 1)
            p.text(x + w / 2, y + h / 2 - 3.5, name, 8, rgb=S().on_accent if on else S().ink, bold=on, center=True)
            p.link(x, y, w, h, self.month_page[m])

    def arrows(self, p, i):
        y = mp.H - 70
        if i > 0:
            p.text(self.right - 54, y, "<", 18, rgb=S().accent, bold=True)
            p.link(self.right - 60, y - 8, 26, 28, self.period_page[i - 1])
        if i < len(self.periods) - 1:
            p.text(self.right - 14, y, ">", 18, rgb=S().accent, bold=True)
            p.link(self.right - 20, y - 8, 26, 28, self.period_page[i + 1])

    def month_name(self, m):
        first = self.months[m]
        return f"{MONTHS[first.month - 1]} {first.year}" if self.dated else f"Month {m + 1}  ________________"

    # Pages

    def year(self, p):
        left, right = 40, self.right
        header(p, left, mp.H - 66, self.title, 30)
        span = (f"{MONTHS[self.months[0].month - 1]} {self.months[0].year} - "
                f"{MONTHS[self.months[11].month - 1]} {self.months[11].year}") if self.dated else "Undated: fill in your own dates"
        p.text(left, mp.H - 88, span, 11, rgb=S().soft)
        cols = 4 if self.landscape else 3
        rows = 12 // cols
        top = mp.H - 112
        gw, gh = (right - left) / cols, (top - 40) / rows
        for m in range(12):
            cx, cy = left + (m % cols) * gw, top - (m // cols + 1) * gh
            p.rect(cx + 4, cy + 4, gw - 8, gh - 8, stroke=S().rule)
            first = self.months[m]
            name = MONTHS[first.month - 1] if self.dated else f"Month {m + 1}"
            p.text(cx + 12, cy + gh - 24, name, 11, rgb=S().accent, bold=True)
            cw = (gw - 24) / 7
            for i, d in enumerate("MTWTFSS"):
                p.text(cx + 12 + i * cw + cw / 2, cy + gh - 40, d, 7, rgb=S().soft, center=True)
            if self.dated:
                weeks = calendar.Calendar(0).monthdayscalendar(first.year, first.month)
                for r, week in enumerate(weeks):
                    for i, day in enumerate(week):
                        if day:
                            p.text(cx + 12 + i * cw + cw / 2, cy + gh - 54 - r * 12, str(day), 7, center=True)
            p.link(cx + 4, cy + 4, gw - 8, gh - 8, self.month_page[m])
        self.tabs(p, "year")

    def month(self, p, m):
        left, right = 40, self.right
        header(p, left, mp.H - 66, self.month_name(m), 26 if self.dated else 22)
        p.link(left, mp.H - 74, 260, 30, self.year_page)
        grid_top = mp.H - 100
        cw = (right - left) / 7
        for i, d in enumerate(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]):
            p.text(left + i * cw + 6, grid_top + 6, d, 9, rgb=S().soft, bold=True)
        bottom = 150 if not self.landscape else 40
        rows = 6
        if self.dated:
            first = self.months[m]
            weeks = calendar.Calendar(0).monthdatescalendar(first.year, first.month)
            rows = len(weeks)
        rh = (grid_top - bottom) / rows
        for r in range(rows):
            y = grid_top - (r + 1) * rh
            for i in range(7):
                x = left + i * cw
                p.rect(x, y, cw, rh, stroke=S().rule)
                if self.dated:
                    day = weeks[r][i]
                    inside = day.month == self.months[m].month
                    p.text(x + 6, y + rh - 14, str(day.day), 10, rgb=S().ink if inside else S().rule, bold=inside)
                    if self.unit == "day" and inside:
                        p.link(x, y, cw, rh, self.period_of(day))
                elif self.unit == "day":
                    n = r * 7 + i + 1
                    if n <= 31:
                        p.text(x + 6, y + rh - 14, str(n), 10, rgb=S().soft)
                        p.link(x, y, cw, rh, self.period_page[m * 31 + n - 1])
            if self.unit == "week":
                if self.dated:
                    target = self.period_of(weeks[r][0])
                else:
                    in_month = [i for i in range(len(self.periods)) if self.month_of(i) == m]
                    if r >= len(in_month):
                        continue
                    target = self.period_page[in_month[r]]
                p.rect(left - 30, y, 26, rh, fill=S().tab)
                p.text(left - 17, y + rh / 2 - 3, f"W{target - self.period_page[0] + 1}", 7.5,
                       rgb=S().accent, bold=True, center=True)
                p.link(left - 30, y, 26 + 7 * cw, rh, target)
        if not self.landscape:
            p.text(left, 128, "Goals & notes", 11, rgb=S().accent, bold=True)
            for i in range(4):
                p.line(left, 110 - i * 24, right, 110 - i * 24)
        self.tabs(p, m)

    def period(self, p, i, body):
        m = self.month_of(i)
        left = 40
        if self.unit == "day":
            if self.dated:
                day = self.periods[i]
                title, sub = DAYS[day.weekday()], f"{MONTHS[day.month - 1]} {day.day}, {day.year}"
            else:
                mm, d = self.periods[i]
                title, sub = f"Day {d}", f"Month {mm + 1}   Date  ________________"
        else:
            if self.dated:
                monday = self.periods[i]
                sunday = monday + dt.timedelta(days=6)
                title = f"Week {i + 1}"
                sub = f"{MONTHS[monday.month - 1][:3]} {monday.day} - {MONTHS[sunday.month - 1][:3]} {sunday.day}, {sunday.year}"
            else:
                title, sub = f"Week {i + 1}", "Week of  ________________"
        header(p, left, mp.H - 66, title, 24)
        p.text(left, mp.H - 86, sub, 11, rgb=S().soft)
        p.link(left, mp.H - 92, 200, 20, self.month_page[m])
        self.arrows(p, i)
        body(self, p, i, left, self.right, mp.H - 104)
        self.tabs(p, m)

    def build(self, body, front_draw=()):
        pages = [Page() for _ in range(1 + len(self.front) + 12 + len(self.periods))]
        self.year(pages[0])
        for k, draw in enumerate(front_draw):
            draw(self, pages[1 + k])
        for m in range(12):
            self.month(pages[self.month_page[m]], m)
        for i in range(len(self.periods)):
            self.period(pages[self.period_page[i]], i, body)
        year_title = str(self.start.year) if self.dated else "Year"
        sections = [{"title": "Overview", "pages": [{"pdfPage": 1, "title": year_title}] + [
            {"pdfPage": idx + 1, "title": name} for idx, name in zip(self.front_pages, self.front)]}]
        sections.append({"title": "Months", "pages": [
            {"pdfPage": self.month_page[m] + 1,
             "title": MONTHS[self.months[m].month - 1] if self.dated else f"Month {m + 1}"} for m in range(12)]})
        unit_title = "Days" if self.unit == "day" else "Weeks"
        sections.append({"title": unit_title, "pages": [
            {"pdfPage": self.period_page[i] + 1, "title": self.period_title(i)} for i in range(len(self.periods))]})
        return pages, {"mode": "notebook", "sections": sections}

    def period_title(self, i):
        if self.unit == "week":
            return f"Week {i + 1}"
        if self.dated:
            d = self.periods[i]
            return f"{MONTHS[d.month - 1][:3]} {d.day}"
        m, d = self.periods[i]
        return f"Month {m + 1}, day {d}"


# Page bodies: what goes under a day's or week's title.

def _lines(p, x0, x1, top, bottom, gap=24):
    y = top
    while y >= bottom:
        p.line(x0, y, x1, y)
        y -= gap


def _label(p, x, y, text, size=10):
    p.text(x, y, text, size, rgb=S().accent, bold=True)


def _checks(p, x0, x1, top, count, gap=24):
    for k in range(count):
        y = top - k * gap
        p.rect(x0, y - 2, 10, 10, stroke=S().soft, width=1)
        p.line(x0 + 18, y - 3, x1, y - 3)


def classic_day(book, p, i, left, right, top):
    """A diary page: a short 'today' box, then lines."""
    p.rect(left, top - 58, right - left, 50, fill=tint(S().accent, 0.92))
    p.text(left + 10, top - 26, "Weather", 9, rgb=S().soft, bold=True)
    p.text(left + 150, top - 26, "Mood", 9, rgb=S().soft, bold=True)
    p.text(left + 280, top - 26, "Grateful for", 9, rgb=S().soft, bold=True)
    for x in (left + 10, left + 150, left + 280):
        p.line(x, top - 46, x + (120 if x < left + 280 else right - left - 300), top - 46)
    _lines(p, left, right, top - 86, 44, 24)


def modern_day(book, p, i, left, right, top):
    """Time blocks on the left; priorities, to-do and notes on the right."""
    mid = left + (right - left) * 0.5
    _label(p, left, top - 14, "Schedule")
    gap = (top - 36 - 50) / 16
    for k, hour in enumerate(range(6, 23)):
        y = top - 36 - k * gap
        h12 = hour % 12 or 12
        p.text(left, y + 4, f"{h12}{'a' if hour < 12 else 'p'}", 8, rgb=S().soft, bold=True)
        p.line(left + 22, y, mid - 14, y)
        p.line(left + 22, y - gap / 2, mid - 14, y - gap / 2, rgb=tint(S().rule, 0.5), width=0.5)
    _label(p, mid, top - 14, "Top 3")
    for k in range(3):
        y = top - 40 - k * 28
        circle(p, mid + 6, y + 3, 6, S().accent, fill=False, width=1)
        p.line(mid + 18, y - 2, right, y - 2)
    _label(p, mid, top - 140, "To-do")
    _checks(p, mid, right, top - 164, 9)
    _label(p, mid, top - 390, "Notes")
    _lines(p, mid, right, top - 412, 44, 24)


def tabbed_day(book, p, i, left, right, top):
    """Lined with a small habit row and water glasses."""
    _label(p, left, top - 14, "Today")
    _checks(p, left, right, top - 38, 4)
    _label(p, left, top - 152, "Notes")
    _lines(p, left, right, top - 176, 104, 24)
    p.text(left, 76, "Water", 9, rgb=S().soft, bold=True)
    for k in range(8):
        p.rect(left + 44 + k * 18, 70, 12, 14, stroke=S().rule)
    p.text(left + 210, 76, "Sleep  ____ h", 9, rgb=S().soft, bold=True)
    p.text(left + 310, 76, "Move  ____ min", 9, rgb=S().soft, bold=True)
    p.text(left, 52, "Highlight", 9, rgb=S().soft, bold=True)
    p.line(left + 52, 49, right, 49)


def week_boxes(book, p, i, left, right, top):
    """A box per day in two columns, plus notes, with links to each day's
    month."""
    bw = (right - left - 12) / 2
    bh = (top - 40 - 3 * 12) / 4
    monday = book.periods[i] if book.dated else None
    for b in range(8):
        x = left + (b % 2) * (bw + 12)
        y = top - (b // 2 + 1) * bh - (b // 2) * 12
        p.rect(x, y, bw, bh, stroke=S().rule)
        if b == 7:
            _label(p, x + 10, y + bh - 18, "Notes")
        else:
            _label(p, x + 10, y + bh - 18, DAYS[b])
            if monday:
                day = monday + dt.timedelta(days=b)
                p.text(x + bw - 10, y + bh - 18, f"{MONTHS[day.month - 1][:3]} {day.day}", 9, rgb=S().soft, right=True)
        _lines(p, x + 10, x + bw - 10, y + bh - 30, y + 10, 22)


def week_columns(book, p, i, left, right, top):
    """Landscape: seven day columns and a notes strip."""
    cw = (right - left) / 7
    monday = book.periods[i] if book.dated else None
    for d in range(7):
        x = left + d * cw
        p.rect(x, 96, cw, top - 96, stroke=S().rule)
        p.rect(x, top - 26, cw, 26, fill=S().tab)
        name = DAYS[d][:3]
        if monday:
            day = monday + dt.timedelta(days=d)
            name += f"  {day.day}"
        p.text(x + 8, top - 17, name, 10, rgb=S().accent, bold=True)
        _lines(p, x + 6, x + cw - 6, top - 50, 104, 22)
    _label(p, left, 80, "This week")
    _checks(p, left + 70, left + (right - left) / 2, 82, 2)
    _label(p, left + (right - left) / 2 + 12, 80, "Notes")
    _lines(p, left + (right - left) / 2 + 60, right, 76, 40, 22)


def academic_week(book, p, i, left, right, top):
    """Days down the side with room for classes, homework and due dates."""
    monday = book.periods[i]
    w = right - left
    cols = [("", 0), ("Classes & notes", 0.18), ("Homework", 0.56), ("Due", 0.86)]
    p.rect(left, top - 22, w, 22, fill=S().tab)
    for name, at in cols:
        _label(p, left + w * at + 6, top - 15, name, 9)
    rh = (top - 22 - 120) / 7
    for d in range(7):
        y = top - 22 - (d + 1) * rh
        day = monday + dt.timedelta(days=d)
        _label(p, left + 6, y + rh - 16, DAYS[d][:3], 10)
        p.text(left + 6, y + rh - 30, f"{MONTHS[day.month - 1][:3]} {day.day}", 8, rgb=S().soft)
        p.line(left, y, right, y)
        for _, at in cols[1:]:
            p.line(left + w * at, y, left + w * at, y + rh, rgb=tint(S().rule, 0.3), width=0.6)
        _lines(p, left + w * 0.18 + 6, right - 6, y + rh - 18, y + 6, 18)
    _label(p, left, 104, "This week's focus")
    _lines(p, left, right, 84, 44, 22)


def lesson_week(book, p, i, left, right, top):
    """Teacher: periods across, days down."""
    monday = book.periods[i]
    periods = 6
    name_w = 64
    cw = (right - left - name_w) / periods
    for k in range(periods):
        p.rect(left + name_w + k * cw, top - 24, cw, 24, fill=S().tab)
        _label(p, left + name_w + k * cw + 8, top - 16, f"Period {k + 1}", 9)
    rh = (top - 24 - 40) / 5
    for d in range(5):
        y = top - 24 - (d + 1) * rh
        day = monday + dt.timedelta(days=d)
        _label(p, left, y + rh - 16, DAYS[d][:3], 10)
        p.text(left, y + rh - 30, f"{MONTHS[day.month - 1][:3]} {day.day}", 8, rgb=S().soft)
        for k in range(periods):
            p.rect(left + name_w + k * cw, y, cw, rh, stroke=S().rule)
            _lines(p, left + name_w + k * cw + 6, left + name_w + (k + 1) * cw - 6, y + rh - 20, y + 8, 18)


# Front pages for the academic and teacher planners.

def _front_table(title, cols, rows, row_h=26):
    def draw(book, p):
        left, right = 40, book.right
        header(p, left, mp.H - 66, title, 26)
        top = mp.H - 96
        w = right - left
        p.rect(left, top - 22, w, 22, fill=S().tab)
        for name, at in cols:
            _label(p, left + w * at + 6, top - 15, name, 9)
        for r in range(rows):
            y = top - 22 - (r + 1) * row_h
            p.line(left, y, right, y)
        for _, at in cols[1:]:
            p.line(left + w * at, top - 22, left + w * at, top - 22 - rows * row_h, rgb=tint(S().rule, 0.3), width=0.6)
        book.tabs(p)
    return draw


def _class_schedule(book, p):
    left, right = 40, book.right
    header(p, left, mp.H - 66, "Class schedule", 26)
    top = mp.H - 96
    tw = 44
    cw = (right - left - tw) / 5
    for i, d in enumerate(["Mon", "Tue", "Wed", "Thu", "Fri"]):
        p.rect(left + tw + i * cw, top - 24, cw, 24, fill=S().tab)
        _label(p, left + tw + i * cw + 8, top - 16, d)
    rh = (top - 24 - 50) / 10
    for r in range(10):
        y = top - 24 - (r + 1) * rh
        p.text(left, y + rh - 14, f"{r + 1}", 9, rgb=S().soft, bold=True)
        for i in range(5):
            p.rect(left + tw + i * cw, y, cw, rh, stroke=S().rule, width=0.6)
    book.tabs(p)


def _seating(book, p):
    left, right = 40, book.right
    header(p, left, mp.H - 66, "Seating chart", 26)
    p.text(left, mp.H - 88, "Class  ________________", 11, rgb=S().soft)
    p.rect(left + (right - left) / 2 - 80, mp.H - 130, 160, 26, fill=S().tab)
    p.text((left + right) / 2, mp.H - 121, "Front", 10, rgb=S().accent, bold=True, center=True)
    cols, rows = 5, 6
    gw, gh = (right - left) / cols, (mp.H - 160 - 50) / rows
    for r in range(rows):
        for c in range(cols):
            x, y = left + c * gw + 8, mp.H - 160 - (r + 1) * gh + 8
            p.rect(x, y, gw - 16, gh - 16, stroke=S().rule)
    book.tabs(p)


ACADEMIC_FRONT = [
    ("Class schedule", _class_schedule),
    ("Assignments", _front_table("Assignments", [("Done", 0), ("Class", 0.08), ("Assignment", 0.3), ("Due", 0.78), ("Grade", 0.9)], 22)),
    ("Exams", _front_table("Exams", [("Subject", 0), ("Date", 0.32), ("Time", 0.48), ("Room", 0.62), ("Topics", 0.76)], 22)),
    ("Grades", _front_table("Grades", [("Course", 0), ("Term 1", 0.4), ("Term 2", 0.55), ("Term 3", 0.7), ("Final", 0.85)], 22)),
]
TEACHER_FRONT = [
    ("Class list", _front_table("Class list", [("#", 0), ("Student", 0.06), ("Contact", 0.45), ("Notes", 0.72)], 24, row_h=24)),
    ("Gradebook", _front_table("Gradebook", [("Student", 0)] + [(f"{k + 1}", 0.3 + k * 0.07) for k in range(10)], 24, row_h=24)),
    ("Seating chart", _seating),
    ("Timetable", _class_schedule),
]


# The books. "dated": needs a year; "start": the first month.

BOOKS = {
    "diary_classic": dict(name="Classic Daily Diary", style=CLASSIC, unit="day", body=classic_day, start=1,
                          price="3.99", tags=["diary", "daily", "dated", "linked"]),
    "diary_modern": dict(name="Modern Daily Planner", style=MODERN, unit="day", body=modern_day, start=1,
                         price="3.99", tags=["planner", "daily", "time blocks", "dated", "linked"]),
    "diary_landscape": dict(name="Landscape Weekly Planner", style=LANDSCAPE, unit="week", body=week_columns, start=1,
                            landscape=True, price="3.99", tags=["planner", "weekly", "landscape", "dated", "linked"]),
    "tabbed_lavender": dict(name="Tabbed Diary: Lavender", style=LAVENDER, unit="day", body=tabbed_day, start=1,
                            tabs="lavender", price="3.99", tags=["diary", "tabbed", "pastel", "dated"]),
    "tabbed_linen": dict(name="Tabbed Diary: Linen", style=LINEN, unit="day", body=tabbed_day, start=1,
                         tabs="linen", price="3.99", tags=["diary", "tabbed", "neutral", "dated"]),
    "tabbed_sorbet": dict(name="Tabbed Diary: Sorbet", style=SORBET, unit="day", body=tabbed_day, start=1,
                          tabs="sorbet", price="3.99", tags=["diary", "tabbed", "colourful", "dated"]),
    "academic_planner": dict(name="Academic Planner", style=ACADEMIC, unit="week", body=academic_week, start=7,
                             front=ACADEMIC_FRONT, price="3.99", category="study",
                             tags=["student", "school year", "weekly", "dated"]),
    "teacher_planner": dict(name="Teacher Planner", style=TEACHER, unit="week", body=lesson_week, start=7,
                            front=TEACHER_FRONT, price="3.99", category="study",
                            tags=["teacher", "lesson plans", "school year", "dated"]),
    "undated_weekly": dict(name="Undated Weekly Planner", style=UNDATED, unit="week", body=week_boxes, dated=False,
                           price="2.99", tags=["planner", "weekly", "undated", "linked"]),
    "undated_daily": dict(name="Undated Daily Planner", style=UNDATED, unit="day", body=modern_day, dated=False,
                          price="2.99", tags=["planner", "daily", "undated", "linked"]),
}


def item_id(key, year):
    book = BOOKS[key]
    if not book.get("dated", True):
        return key
    return f"{key}_{year}" if book.get("start", 1) == 1 else f"{key}_{year}_{(year + 1) % 100:02d}"


def write(key, year):
    book = BOOKS[key]
    dated = book.get("dated", True)
    mp.use_size(*((792, 612) if book.get("landscape") else (612, 792)))
    mp.use_style(book["style"])
    start = dt.date(year, book.get("start", 1), 1)
    title = book["name"].split(":")[0] if not dated else (
        str(year) if book.get("start", 1) == 1 else f"{year}-{(year + 1) % 100:02d}")
    front = book.get("front", [])
    b = Book(title, start, book["unit"], dated=dated, front=[n for n, _ in front],
             tabs=RAINBOW.get(book.get("tabs")), landscape=book.get("landscape", False))
    pages, spec = b.build(book["body"], [draw for _, draw in front])
    iid = item_id(key, year)
    folder = ROOT / "catalog" / iid
    folder.mkdir(parents=True, exist_ok=True)
    mp.write_pdf(pages, folder / "template.pdf")
    (folder / "template.json").write_text(json.dumps(spec, indent=2) + "\n")
    mp.write_preview(folder / "template.pdf", folder / "preview.webp")
    name = book["name"]
    if dated:
        name += f" {title}"
    product = f"planner_{key}_{year}" if dated else f"pack_{key}"
    listing = {
        "kind": "template",
        "name": name,
        "version": 1,
        "unlock": {"pro": True, "products": [product]},
        "category": book.get("category", "diaries"),
        "tags": book["tags"] + ([str(year)] if dated else []),
    }
    path = folder / "listing.json"
    if path.exists():
        listing["version"] = json.loads(path.read_text()).get("version", 1)
    path.write_text(json.dumps(listing, indent=2) + "\n")
    mp.use_size(612, 792)
    return iid, len(pages)


def main():
    args = sys.argv[1:]
    if args == ["--list"]:
        for key, book in BOOKS.items():
            print(f"{key:20} ${book['price']:5} {book['name']}")
        return
    if len(args) != 2 or (args[0] != "all" and args[0] not in BOOKS):
        sys.exit(__doc__)
    year = int(args[1])
    for key in BOOKS if args[0] == "all" else [args[0]]:
        iid, count = write(key, year)
        print(f"{iid}: {count} pages")


if __name__ == "__main__":
    main()

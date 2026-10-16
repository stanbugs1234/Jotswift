"""The linked planner: every Jotswift planner and diary is built here, so
they all drill down the same way.

Pages, in order: Home, the year, Year goals, Year in pixels, any front
pages, each month (its calendar, then Goals, Habits and Notes), the weeks,
the days, then Notes and Lists, each with an index page.

Every page has a trail back up (Home > 2027 > March > Week 10 > Wed 10)
with arrows to the pages beside it, tabs down the right edge, and a link
on every date: year and month calendars, Year in pixels, habit trackers,
week headings and each day's small month calendar all open the day.

  book = Planner("2027", dt.date(2027, 1, 1), week_body=week_boxes, day_body=day_plan)
  pages, spec = book.build()
"""

import calendar
import datetime as dt

import make_planner as mp
from make_planner import Page, circle, header, text_width, tint

MONTHS = list(calendar.month_name)[1:]
DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
NOTE_PAGES = 20
LISTS = ["Books to read", "Movies & shows", "Groceries", "Gift ideas", "Birthdays",
         "Places to go", "Wishlist", "Ideas", "Packing list", "Checklist"]
GOAL_AREAS = ["Personal", "Health", "Work & study", "Money", "Relationships", "Fun"]
LEFT = 40


def S():
    return mp.S


def rgb(hex_):
    h = hex_.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def add_months(d, n):
    y, m = divmod(d.month - 1 + n, 12)
    return dt.date(d.year + y, m + 1, 1)


def chevron(p, x, y, size, rgb_, back=False, width=1.2):
    """A small > (or < when [back]) with its point at mid-height."""
    dx = -size / 2 if back else size / 2
    x0 = x + size / 4 if back else x - size / 4
    p.color(rgb_, stroke=True)
    p.ops.append(f"{width} w 1 J 1 j {x0:.1f} {y + size / 2:.1f} m {x0 + dx:.1f} {y:.1f} l "
                 f"{x0:.1f} {y - size / 2:.1f} l S")


# Page bodies shared by planners: (book, page, index, left, right, top).

def lines(p, x0, x1, top, bottom, gap=24):
    y = top
    while y >= bottom:
        p.line(x0, y, x1, y)
        y -= gap


def label(p, x, y, text, size=10):
    p.text(x, y, text, size, rgb=S().accent, bold=True)


def checks(p, x0, x1, top, count, gap=24):
    for k in range(count):
        y = top - k * gap
        p.rect(x0, y - 2, 10, 10, stroke=S().soft, width=1)
        p.line(x0 + 18, y - 3, x1, y - 3)


def week_boxes(book, p, i, left, right, top):
    """A box per day in two columns, plus notes. Each day's heading opens
    its day page."""
    bw = (right - left - 12) / 2
    bh = (top - 40 - 3 * 12) / 4
    days = book.week_days(i)
    for b in range(8):
        x = left + (b % 2) * (bw + 12)
        y = top - (b // 2 + 1) * bh - (b // 2) * 12
        p.rect(x, y, bw, bh, stroke=S().rule)
        if b == 7:
            label(p, x + 10, y + bh - 18, "Notes")
        else:
            label(p, x + 10, y + bh - 18, DAYS[b])
            if days:
                day = days[b]
                p.text(x + bw - 22, y + bh - 18, f"{MONTHS[day.month - 1][:3]} {day.day}", 9,
                       rgb=S().soft, right=True)
                if book.link_day(p, x, y + bh - 28, bw, 28, day):
                    chevron(p, x + bw - 12, y + bh - 15, 7, S().accent)
        lines(p, x + 10, x + bw - 10, y + bh - 30, y + 10, 22)


def day_plan(book, p, i, left, right, top):
    """Time blocks on the left; top 3, to-do and notes on the right."""
    mid = left + (right - left) * 0.5
    label(p, left, top - 14, "Schedule")
    gap = (top - 36 - 50) / 16
    for k, hour in enumerate(range(6, 23)):
        y = top - 36 - k * gap
        h12 = hour % 12 or 12
        p.text(left, y + 4, f"{h12}{'a' if hour < 12 else 'p'}", 8, rgb=S().soft, bold=True)
        p.line(left + 22, y, mid - 14, y)
        p.line(left + 22, y - gap / 2, mid - 14, y - gap / 2, rgb=tint(S().rule, 0.5), width=0.5)
    label(p, mid, top - 14, "Top 3")
    for k in range(3):
        y = top - 40 - k * 28
        circle(p, mid + 6, y + 3, 6, S().accent, fill=False, width=1)
        p.line(mid + 18, y - 2, right, y - 2)
    label(p, mid, top - 140, "To-do")
    count = max(4, min(9, int((top - 164 - 150) / 24) + 1))
    checks(p, mid, right, top - 164, count)
    notes = top - 164 - count * 24 - 10
    label(p, mid, notes, "Notes")
    lines(p, mid, right, notes - 22, 44, 24)


class Planner:
    """A dated book of twelve months from [start], or an undated one.

    [week_body] and [day_body] draw under a week's or day's title. [front]
    is a list of (title, draw(book, page)) pages after Year in pixels.
    [tab_colors] gives each month tab its own colour (hex)."""

    def __init__(self, title, start, dated=True, *, week_body, day_body, front=(),
                 tab_colors=None, subtitle="Planner"):
        self.title, self.start, self.dated = title, start, dated
        self.week_body, self.day_body = week_body, day_body
        self.front = list(front)
        self.tab_colors = tab_colors
        self.subtitle = subtitle
        self.months = [add_months(start, i) for i in range(12)]
        if dated:
            end = add_months(start, 12)
            self.days = [start + dt.timedelta(days=i) for i in range((end - start).days)]
            monday = start - dt.timedelta(days=start.weekday())
            self.weeks = []
            while monday < end:
                self.weeks.append(monday)
                monday += dt.timedelta(days=7)
            self.day_index = {d: i for i, d in enumerate(self.days)}
        else:
            self.days = [(m, d) for m in range(12) for d in range(1, 32)]
            self.weeks = list(range(52))

        count = 0

        def take(n):
            nonlocal count
            first = count
            count += n
            return first

        self.home = take(1)
        self.year_page = take(1)
        self.goals_page = take(1)
        self.pixels_page = take(1)
        self.front_pages = [take(1) for _ in self.front]
        # Each month: its calendar, then Goals, Habits and Notes.
        self.month_pages = [take(4) for _ in range(12)]
        self.week_page = [take(1) for _ in self.weeks]
        self.day_page = [take(1) for _ in self.days]
        self.notes_page = take(1)
        self.note_pages = [take(1) for _ in range(NOTE_PAGES)]
        self.lists_page = take(1)
        self.list_pages = [take(1) for _ in LISTS]
        self.count = count

    # Where things are

    @property
    def right(self):
        return mp.W - 52

    @property
    def landscape(self):
        return mp.W > mp.H

    def month_page(self, m, sub=0):
        """Month [m]'s calendar, or its Goals (1), Habits (2), Notes (3)."""
        return self.month_pages[m] + sub

    def month_index(self, day):
        for m, first in enumerate(self.months):
            if (first.year, first.month) == (day.year, day.month):
                return m
        return None

    def day_month(self, i):
        return self.month_index(self.days[i]) if self.dated else self.days[i][0]

    def week_month(self, i):
        if not self.dated:
            return min(11, i * 12 // 52)
        m = self.month_index(max(self.weeks[i], self.start))
        return 11 if m is None else m

    def week_of(self, day):
        """The week index holding [day] (dated books), or None."""
        i = (day - self.weeks[0]).days // 7
        return i if 0 <= i < len(self.weeks) else None

    def day_of_month(self, m, n):
        """The day index of day [n] in month [m], or None."""
        if self.dated:
            first = self.months[m]
            if n > calendar.monthrange(first.year, first.month)[1]:
                return None
            return self.day_index.get(dt.date(first.year, first.month, n))
        return m * 31 + n - 1

    def week_days(self, i):
        """The seven dates of week [i], or None when undated."""
        if not self.dated:
            return None
        return [self.weeks[i] + dt.timedelta(days=d) for d in range(7)]

    def link_day(self, p, x, y, w, h, day):
        """Links the area to [day]'s page; False if the book has no such day."""
        i = self.day_index.get(day) if self.dated else None
        if i is None:
            return False
        p.link(x, y, w, h, self.day_page[i])
        return True

    # Names

    def year_short(self):
        if not self.dated:
            return "Yr"
        return self.title[2:] if len(self.title) == 4 else f"{self.title[2:4]}/{self.title[-2:]}"

    def month_name(self, m, short=False):
        if not self.dated:
            return f"M{m + 1}" if short else f"Month {m + 1}"
        name = MONTHS[self.months[m].month - 1]
        return name[:3] if short else name

    def day_name(self, i):
        if not self.dated:
            return f"Day {self.days[i][1]}"
        d = self.days[i]
        return f"{DAYS[d.weekday()][:3]} {d.day}"

    # The frame on every page: trail, arrows and tabs

    def frame(self, p, crumbs, tab, prev=None, next_=None):
        """[crumbs]: (label, page) pairs from Home down; the last is this
        page. [tab]: "home", "year", "notes", "lists" or a month index."""
        x, y = LEFT, mp.H - 38
        for k, (name, target) in enumerate(crumbs):
            if k:
                chevron(p, x + 3, y + 3, 5, S().soft, width=0.9)
                x += 10
            last = k == len(crumbs) - 1
            p.text(x, y, name, 9, rgb=S().ink if last else S().accent, bold=last)
            w = text_width(name, 9)
            if not last:
                p.link(x - 4, y - 9, w + 8, 24, target)
            x += w + 4
        right = self.right
        if prev is not None:
            chevron(p, right - 34, y + 3, 10, S().accent, back=True, width=1.6)
            p.link(right - 48, y - 10, 28, 26, prev)
        if next_ is not None:
            chevron(p, right - 6, y + 3, 10, S().accent, width=1.6)
            p.link(right - 20, y - 10, 28, 26, next_)
        self.tabs(p, tab)

    def tabs(self, p, current=None):
        """Home, the year, twelve months, Notes and Lists down the right edge."""
        entries = [("Home", self.home, "home"), (self.year_short(), self.year_page, "year")]
        entries += [(self.month_name(m, short=True), self.month_page(m), m) for m in range(12)]
        entries += [("Notes", self.notes_page, "notes"), ("Lists", self.lists_page, "lists")]
        x, w = mp.W - 34, 26
        top, bottom, gap = mp.H - 40, 40, 3
        h = (top - bottom - gap * (len(entries) - 1)) / len(entries)
        for k, (name, target, key) in enumerate(entries):
            y = top - (k + 1) * h - k * gap
            on = key == current
            color = rgb(self.tab_colors[key]) if self.tab_colors and isinstance(key, int) else None
            fill = S().accent if on else (tint(color, 0.35) if color else S().tab)
            p.rect(x, y, w, h, fill=fill)
            size = 7 if len(name) > 3 else 8
            ink = S().on_accent if on else (S().ink if color else S().accent)
            p.text(x + w / 2, y + h / 2 - size * 0.35, name, size, rgb=ink, bold=True, center=True)
            p.link(x, y, w, h, target)

    def year_name(self):
        return self.title if self.dated else "Year"

    def crumbs(self, *tail):
        return [("Home", self.home), (self.year_name(), self.year_page), *tail]

    # Pages

    def tiles(self, p, y, title, items, per_row, height, size=10):
        """A labelled grid of linked tiles from [y] down; returns the y below."""
        label(p, LEFT, y, title, 11)
        y -= 12
        gap = 6
        w = (self.right - LEFT - gap * (per_row - 1)) / per_row
        for k, (name, target) in enumerate(items):
            r, c = divmod(k, per_row)
            x, ty = LEFT + c * (w + gap), y - (r + 1) * height - r * gap
            p.rect(x, ty, w, height, fill=S().tab)
            p.text(x + w / 2, ty + height / 2 - size * 0.35, name, size, rgb=S().accent, bold=True, center=True)
            p.link(x, ty, w, height, target)
        rows = (len(items) + per_row - 1) // per_row
        return y - rows * (height + gap) - 22

    def draw_home(self, p):
        header(p, LEFT, mp.H - 70, self.title, 34)
        p.text(LEFT, mp.H - 94, self.subtitle, 12, rgb=S().soft)
        wide = self.landscape
        y = mp.H - 126
        planner = [("Year", self.year_page), ("Goals", self.goals_page), ("Year in pixels", self.pixels_page)]
        planner += [(name, page) for (name, _), page in zip(self.front, self.front_pages)]
        planner += [("Notes", self.notes_page), ("Lists", self.lists_page)]
        y = self.tiles(p, y, "Planner", planner, 6 if wide else 5, 40 if wide else 62, size=11)
        months = [(self.month_name(m), self.month_page(m)) for m in range(12)]
        y = self.tiles(p, y, "Months", months, 6, 30 if wide else 46)
        weeks = [(str(i + 1), page) for i, page in enumerate(self.week_page)]
        y = self.tiles(p, y, "Weeks", weeks, 18 if wide else 14, 18 if wide else 28, size=9)
        hint = "Tap a date, tab or title with your finger to go there. The Pencil always writes."
        p.text(LEFT, 58, hint, 9, rgb=S().soft)
        if self.dated:
            p.text(LEFT, 44, "Tap Today at the top of the screen to open today's page.", 9, rgb=S().soft)
        self.frame(p, [], "home")

    def mini_month(self, p, m, x, top, w, row_h, size, today=None, week_links=False):
        """Month [m]'s dates in a small grid whose dates open their day.
        Returns the grid's bottom."""
        cols = 8 if week_links else 7
        cw = w / cols
        x0 = x + (cw if week_links else 0)
        if self.dated:
            first = self.months[m]
            for k, d in enumerate("MTWTFSS"):
                p.text(x0 + k * cw + cw / 2, top, d, size - 1, rgb=S().soft, center=True)
            weeks = calendar.Calendar(0).monthdatescalendar(first.year, first.month)
        else:
            weeks = [[(r * 7 + k + 1) for k in range(7)] for r in range(5)]
        y = top
        for r, week in enumerate(weeks):
            y = top - (r + 1) * row_h
            if week_links and self.dated:
                wi = self.week_of(week[0])
                if wi is not None:
                    p.text(x + cw / 2, y, f"W{wi + 1}", size - 1.5, rgb=S().accent, bold=True, center=True)
                    p.link(x, y - row_h * 0.3, cw, row_h, self.week_page[wi])
            for k, day in enumerate(week):
                cx = x0 + k * cw + cw / 2
                if self.dated:
                    if day.month != self.months[m].month:
                        continue
                    n, i = day.day, self.day_index.get(day)
                else:
                    if day > 31:
                        continue
                    n, i = day, self.day_of_month(m, day)
                if i is not None and i == today:
                    circle(p, cx, y + size * 0.33, size * 0.85, S().accent)
                    p.text(cx, y, str(n), size, rgb=S().on_accent, bold=True, center=True)
                else:
                    p.text(cx, y, str(n), size, center=True)
                if i is not None:
                    p.link(cx - cw / 2, y - row_h * 0.3, cw, row_h, self.day_page[i])
        return y - row_h * 0.3

    def draw_year(self, p):
        header(p, LEFT, mp.H - 70, self.year_name(), 30)
        p.text(LEFT, mp.H - 92, "Tap a month, a week or any date.", 11, rgb=S().soft)
        cols = 4 if self.landscape else 3
        rows = 12 // cols
        top = mp.H - 108
        gw, gh = (self.right - LEFT) / cols, (top - 40) / rows
        for m in range(12):
            cx, cy = LEFT + (m % cols) * gw, top - (m // cols + 1) * gh
            p.rect(cx + 4, cy + 4, gw - 8, gh - 8, stroke=S().rule)
            name = self.month_name(m)
            p.text(cx + 12, cy + gh - 24, name, 11, rgb=S().accent, bold=True)
            p.link(cx + 4, cy + gh - 32, gw - 8, 28, self.month_page(m))
            self.mini_month(p, m, cx + 8, cy + gh - 42, gw - 16, min(18, (gh - 54) / 6), 8,
                            week_links=self.dated)
        self.frame(p, self.crumbs(), "year")

    def draw_goals(self, p):
        header(p, LEFT, mp.H - 70, "Goals", 28)
        p.text(LEFT, mp.H - 92, "For the year, then month by month:", 11, rgb=S().soft)
        right = self.right
        gap = 4
        cw = (right - LEFT - gap * 11) / 12
        y = mp.H - 126
        for m in range(12):
            x = LEFT + m * (cw + gap)
            p.rect(x, y, cw, 22, fill=S().tab)
            p.text(x + cw / 2, y + 7, self.month_name(m, short=True), 8, rgb=S().accent, bold=True, center=True)
            p.link(x, y, cw, 22, self.month_page(m, 1))
        cols = 3 if self.landscape else 2
        rows = len(GOAL_AREAS) // cols
        top, bottom = y - 14, 44
        bw = (right - LEFT - 12 * (cols - 1)) / cols
        bh = (top - bottom - 12 * (rows - 1)) / rows
        for k, area in enumerate(GOAL_AREAS):
            x = LEFT + (k % cols) * (bw + 12)
            by = top - (k // cols + 1) * bh - (k // cols) * 12
            p.rect(x, by, bw, bh, stroke=S().rule)
            label(p, x + 10, by + bh - 18, area)
            checks(p, x + 10, x + bw - 10, by + bh - 40, int((bh - 40) / 24))
        self.frame(p, self.crumbs(("Goals", self.goals_page)), "year")

    def draw_pixels(self, p):
        header(p, LEFT, mp.H - 70, "Year in pixels", 28)
        p.text(LEFT, mp.H - 92, "Colour each day by mood, or anything you track. Tap a date to open it.",
               10, rgb=S().soft)
        right = self.right
        name_w = 22
        cw = (right - LEFT - name_w) / 12
        top, bottom = mp.H - 112, 96
        rh = (top - 16 - bottom) / 31
        for m in range(12):
            x = LEFT + name_w + m * cw
            p.text(x + cw / 2, top - 10, self.month_name(m, short=True), 8, rgb=S().accent, bold=True, center=True)
            p.link(x, top - 16, cw, 20, self.month_page(m))
        for n in range(1, 32):
            y = top - 16 - n * rh
            p.text(LEFT + name_w - 6, y + rh / 2 - 3, str(n), 7, rgb=S().soft, right=True)
            for m in range(12):
                i = self.day_of_month(m, n)
                if i is None:
                    continue
                x = LEFT + name_w + m * cw
                p.rect(x + 1.5, y + 1, cw - 3, rh - 2, stroke=S().rule, width=0.6)
                p.link(x, y, cw, rh, self.day_page[i])
        label(p, LEFT, 70, "Key", 10)
        kw = (right - LEFT - 40) / 5
        for k in range(5):
            x = LEFT + 40 + k * kw
            p.rect(x, 62, 14, 14, stroke=S().soft, width=0.8)
            p.line(x + 20, 62, x + kw - 12, 62)
        self.frame(p, self.crumbs(("Year in pixels", self.pixels_page)), "year")

    def draw_front(self, p, k):
        name, draw = self.front[k]
        draw(self, p)
        self.frame(p, [("Home", self.home), (name, self.front_pages[k])], "home",
                   prev=self.front_pages[k - 1] if k else None,
                   next_=self.front_pages[k + 1] if k + 1 < len(self.front) else None)

    def month_title(self, m):
        first = self.months[m]
        return f"{MONTHS[first.month - 1]} {first.year}" if self.dated else f"Month {m + 1}"

    def month_frame(self, p, m, sub, name=None):
        crumbs = self.crumbs((self.month_name(m), self.month_page(m)))
        if name:
            crumbs.append((name, self.month_page(m, sub)))
        self.frame(p, crumbs, m,
                   prev=self.month_page(m - 1, sub) if m else None,
                   next_=self.month_page(m + 1, sub) if m < 11 else None)

    def month_chips(self, p, m, current):
        """Calendar, Goals, Habits and Notes for month [m], at the top right."""
        names = ["Calendar", "Goals", "Habits", "Notes"]
        w, gap = 54, 4
        x = self.right - 4 * w - 3 * gap
        y = mp.H - 82
        for k, name in enumerate(names):
            on = k == current
            p.rect(x, y, w, 22, fill=S().accent if on else S().tab)
            p.text(x + w / 2, y + 7, name, 8.5, rgb=S().on_accent if on else S().accent, bold=True, center=True)
            if not on:
                p.link(x, y, w, 22, self.month_page(m, k))
            x += w + gap

    def draw_month(self, p, m):
        header(p, LEFT, mp.H - 70, self.month_title(m), 26)
        self.month_chips(p, m, 0)
        right = self.right
        grid_top, grid_left = mp.H - 112, LEFT + 32
        cw = (right - grid_left) / 7
        for k, d in enumerate(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]):
            p.text(grid_left + k * cw + 6, grid_top + 6, d, 9, rgb=S().soft, bold=True)
        if self.dated:
            first = self.months[m]
            weeks = calendar.Calendar(0).monthdatescalendar(first.year, first.month)
        else:
            weeks = [[r * 7 + k + 1 for k in range(7)] for r in range(5)]
            in_month = [i for i in range(len(self.weeks)) if self.week_month(i) == m]
        bottom = 40 if self.landscape else 150
        rh = (grid_top - bottom) / len(weeks)
        for r, week in enumerate(weeks):
            y = grid_top - (r + 1) * rh
            wi = self.week_of(week[0]) if self.dated else (in_month[r] if r < len(in_month) else None)
            if wi is not None:
                p.rect(LEFT, y + 1, 28, rh - 2, fill=S().tab)
                p.text(LEFT + 14, y + rh / 2 - 3, f"W{wi + 1}", 8, rgb=S().accent, bold=True, center=True)
                p.link(LEFT, y, 28, rh, self.week_page[wi])
            for k, day in enumerate(week):
                x = grid_left + k * cw
                p.rect(x, y, cw, rh, stroke=S().rule)
                if self.dated:
                    inside = day.month == self.months[m].month
                    p.text(x + 6, y + rh - 14, str(day.day), 10, rgb=S().ink if inside else S().rule, bold=inside)
                    if inside:
                        self.link_day(p, x, y, cw, rh, day)
                elif day <= 31:
                    p.text(x + 6, y + rh - 14, str(day), 10, rgb=S().soft)
                    p.link(x, y, cw, rh, self.day_page[self.day_of_month(m, day)])
        if not self.landscape:
            label(p, LEFT, 128, "Notes", 11)
            lines(p, LEFT, right, 110, 40, 24)
        self.month_frame(p, m, 0)

    def draw_month_goals(self, p, m):
        header(p, LEFT, mp.H - 70, f"{self.month_name(m)} goals", 26)
        self.month_chips(p, m, 1)
        right = self.right
        mid = LEFT + (right - LEFT) / 2
        top = mp.H - 112
        label(p, LEFT, top, "Focus")
        lines(p, LEFT, mid - 14, top - 26, top - 98, 24)
        label(p, LEFT, top - 126, "Goals")
        checks(p, LEFT, mid - 14, top - 152, int((top - 152 - 40) / 26) + 1, 26)
        label(p, mid, top, "Important dates")
        lines(p, mid, right, top - 26, top - 194, 24)
        label(p, mid, top - 222, "Reflection")
        lines(p, mid, right, top - 248, 44, 24)
        self.month_frame(p, m, 1, "Goals")

    def draw_month_habits(self, p, m):
        header(p, LEFT, mp.H - 70, f"{self.month_name(m)} habits", 26)
        self.month_chips(p, m, 2)
        right = self.right
        if self.dated:
            first = self.months[m]
            count = calendar.monthrange(first.year, first.month)[1]
        else:
            count = 31
        name_w = 104
        cw = (right - LEFT - name_w) / count
        top = mp.H - 116
        for n in range(1, count + 1):
            x = LEFT + name_w + (n - 1) * cw
            p.text(x + cw / 2, top, str(n), 6.5, rgb=S().accent, bold=True, center=True)
            if self.dated:
                d = dt.date(first.year, first.month, n)
                p.text(x + cw / 2, top - 9, "MTWTFSS"[d.weekday()], 5.5, rgb=S().soft, center=True)
            i = self.day_of_month(m, n)
            if i is not None:
                p.link(x, top - 12, cw, 22, self.day_page[i])
        label(p, LEFT, top, "Habit", 9)
        rows = int((top - 20 - 50) / 28)
        for r in range(rows):
            y = top - 20 - (r + 1) * 28
            p.line(LEFT, y + 4, LEFT + name_w - 8, y + 4)
            for n in range(count):
                x = LEFT + name_w + n * cw
                p.rect(x + 1, y + 6, cw - 2, min(cw - 2, 14), stroke=S().rule, width=0.6)
        self.month_frame(p, m, 2, "Habits")

    def draw_month_notes(self, p, m):
        header(p, LEFT, mp.H - 70, f"{self.month_name(m)} notes", 26)
        self.month_chips(p, m, 3)
        lines(p, LEFT, self.right, mp.H - 116, 44, 26)
        self.month_frame(p, m, 3, "Notes")

    def draw_week(self, p, i):
        m = self.week_month(i)
        title = f"Week {i + 1}"
        header(p, LEFT, mp.H - 70, title, 24)
        days = self.week_days(i)
        if days:
            first, last = days[0], days[-1]
            sub = f"{MONTHS[first.month - 1][:3]} {first.day} - {MONTHS[last.month - 1][:3]} {last.day}, {last.year}"
        else:
            sub = "Week of  ________________"
        p.text(LEFT, mp.H - 90, sub, 11, rgb=S().soft)
        self.week_body(self, p, i, LEFT, self.right, mp.H - 106)
        self.frame(p, self.crumbs((self.month_name(m), self.month_page(m)), (title, self.week_page[i])), m,
                   prev=self.week_page[i - 1] if i else None,
                   next_=self.week_page[i + 1] if i + 1 < len(self.weeks) else None)

    def draw_day(self, p, i):
        m = self.day_month(i)
        if self.dated:
            d = self.days[i]
            title, sub = DAYS[d.weekday()], f"{MONTHS[d.month - 1]} {d.day}, {d.year}"
        else:
            mm, n = self.days[i]
            title, sub = f"Day {n}", f"Month {mm + 1}   Date  ________________"
        header(p, LEFT, mp.H - 70, title, 24)
        p.text(LEFT, mp.H - 90, sub, 11, rgb=S().soft)
        # This day's month, small, at the top right; its dates open their days.
        w = 7 * 16
        x = self.right - w
        p.text(x, mp.H - 56, self.month_name(m), 8, rgb=S().accent, bold=True)
        p.link(x - 2, mp.H - 62, w, 14, self.month_page(m))
        self.mini_month(p, m, x, mp.H - 67, w, 9.5, 7, today=i)
        self.day_body(self, p, i, LEFT, self.right, mp.H - 130)
        crumbs = self.crumbs((self.month_name(m), self.month_page(m)))
        if self.dated:
            wi = self.week_of(self.days[i])
            if wi is not None:
                crumbs.append((f"Week {wi + 1}", self.week_page[wi]))
        crumbs.append((self.day_name(i), self.day_page[i]))
        self.frame(p, crumbs, m,
                   prev=self.day_page[i - 1] if i else None,
                   next_=self.day_page[i + 1] if i + 1 < len(self.days) else None)

    def draw_index(self, p, title, names, pages, tab):
        header(p, LEFT, mp.H - 70, title, 28)
        p.text(LEFT, mp.H - 92, "Tap a line to open its page.", 11, rgb=S().soft)
        top, bottom = mp.H - 110, 44
        rh = min(44, (top - bottom) / len(names))
        for k, (name, page) in enumerate(zip(names, pages)):
            y = top - (k + 1) * rh
            p.text(LEFT, y + 8, f"{k + 1}", 10, rgb=S().accent, bold=True)
            if name:
                p.text(LEFT + 26, y + 8, name, 11)
            chevron(p, self.right - 6, y + 11, 8, S().accent)
            p.line(LEFT + 22, y + 4, self.right, y + 4)
            p.link(LEFT, y, self.right - LEFT, rh, page)
        index = self.notes_page if tab == "notes" else self.lists_page
        self.frame(p, [("Home", self.home), (title, index)], tab)

    def draw_note(self, p, k):
        title = f"Note {k + 1}"
        header(p, LEFT, mp.H - 70, title, 24)
        p.text(LEFT, mp.H - 92, "Title", 10, rgb=S().soft, bold=True)
        p.line(LEFT + 34, mp.H - 95, self.right, mp.H - 95)
        lines(p, LEFT, self.right, mp.H - 126, 44, 26)
        pages = self.note_pages
        self.frame(p, [("Home", self.home), ("Notes", self.notes_page), (title, pages[k])], "notes",
                   prev=pages[k - 1] if k else None, next_=pages[k + 1] if k + 1 < len(pages) else None)

    def draw_list(self, p, k):
        title = LISTS[k]
        header(p, LEFT, mp.H - 70, title, 24)
        top = mp.H - 112
        checks(p, LEFT, self.right, top, int((top - 44) / 28) + 1, 28)
        pages = self.list_pages
        self.frame(p, [("Home", self.home), ("Lists", self.lists_page), (title, pages[k])], "lists",
                   prev=pages[k - 1] if k else None, next_=pages[k + 1] if k + 1 < len(pages) else None)

    # The book

    def build(self):
        pages = [Page() for _ in range(self.count)]
        self.draw_home(pages[self.home])
        self.draw_year(pages[self.year_page])
        self.draw_goals(pages[self.goals_page])
        self.draw_pixels(pages[self.pixels_page])
        for k, page in enumerate(self.front_pages):
            self.draw_front(pages[page], k)
        for m in range(12):
            self.draw_month(pages[self.month_page(m)], m)
            self.draw_month_goals(pages[self.month_page(m, 1)], m)
            self.draw_month_habits(pages[self.month_page(m, 2)], m)
            self.draw_month_notes(pages[self.month_page(m, 3)], m)
        for i, page in enumerate(self.week_page):
            self.draw_week(pages[page], i)
        for i, page in enumerate(self.day_page):
            self.draw_day(pages[page], i)
        self.draw_index(pages[self.notes_page], "Notes", [None] * NOTE_PAGES, self.note_pages, "notes")
        for k, page in enumerate(self.note_pages):
            self.draw_note(pages[page], k)
        self.draw_index(pages[self.lists_page], "Lists", LISTS, self.list_pages, "lists")
        for k, page in enumerate(self.list_pages):
            self.draw_list(pages[page], k)
        return pages, self.spec()

    def spec(self):
        def entry(page, title, first=None, last=None):
            e = {"pdfPage": page + 1, "title": title}
            if self.dated and first is not None:
                e.update({"from": first.isoformat(), "to": (last or first).isoformat()})
            return e

        end = add_months(self.start, 12) - dt.timedelta(days=1)
        overview = [entry(self.home, "Home"), entry(self.year_page, self.year_name(), self.start, end),
                    entry(self.goals_page, "Goals"), entry(self.pixels_page, "Year in pixels")]
        overview += [entry(page, name) for (name, _), page in zip(self.front, self.front_pages)]
        months = []
        for m in range(12):
            name = self.month_name(m)
            first = self.months[m]
            last = add_months(first, 1) - dt.timedelta(days=1)
            months.append(entry(self.month_page(m), name, first, last))
            for sub, kind in ((1, "goals"), (2, "habits"), (3, "notes")):
                months.append(entry(self.month_page(m, sub), f"{self.month_name(m, short=True)} {kind}"))
        weeks = [entry(page, f"Week {i + 1}", *((self.weeks[i], self.weeks[i] + dt.timedelta(days=6))
                                                if self.dated else ()))
                 for i, page in enumerate(self.week_page)]
        if self.dated:
            days = [entry(page, f"{MONTHS[d.month - 1][:3]} {d.day}", d) for d, page in zip(self.days, self.day_page)]
        else:
            days = [entry(page, f"Month {m + 1}, day {n}") for (m, n), page in zip(self.days, self.day_page)]
        notes = [entry(self.notes_page, "Notes")] + [entry(page, f"Note {k + 1}") for k, page in enumerate(self.note_pages)]
        lists_ = [entry(self.lists_page, "Lists")] + [entry(page, name) for name, page in zip(LISTS, self.list_pages)]
        return {"mode": "notebook", "sections": [
            {"title": "Overview", "pages": overview},
            {"title": "Months", "pages": months},
            {"title": "Weeks", "pages": weeks},
            {"title": "Days", "pages": days},
            {"title": "Notes", "pages": notes},
            {"title": "Lists", "pages": lists_},
        ]}

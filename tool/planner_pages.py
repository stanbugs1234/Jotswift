"""Page bodies for planner_kit books. Each takes a Ctx (c) and draws in
c.left..c.right, c.top..c.bottom, adapting to landscape or portrait.

Writing space is never cramped: ruled lines are 24pt or more apart, and a
page that needs more room gets a second page in the book instead.
"""

import calendar
import datetime as dt

import make_planner as mp
from make_planner import circle, text_width, tint
from planner_kit import (DAY_NAMES, S, card, checks, chevron, columns, dots, icon, label, lines,
                         rows, rrect, scale)


def _hour(h):
    return f"{h % 12 or 12}{'am' if h < 12 else 'pm'}"


# Shared pieces

def time_blocks(c, x0, x1, top, bottom, start=6, end=22, title="Time blocks"):
    """Hours from [start] to [end], each split in half, to block out."""
    label(c.p, x0, top - 12, title, 10, "calendar")
    top -= 26
    n = end - start
    gap = (top - bottom) / n
    for k in range(n + 1):
        y = top - k * gap
        if k < n:
            c.p.text(x0, y - 10, _hour(start + k), 7.5, rgb=S().soft, bold=True)
            c.p.line(x0 + 30, y - gap / 2, x1, y - gap / 2, rgb=tint(S().rule, 0.5), width=0.5)
        c.p.line(x0 + 30, y, x1, y)


def boxes_list(c, x0, x1, top, n, h=26, numbered=True, big=False):
    """[n] write-in boxes, numbered; returns the bottom."""
    for k in range(n):
        y = top - (k + 1) * h - k * 6
        rrect(c.p, x0, y, x1 - x0, h, 6, stroke=S().rule)
        if numbered:
            c.p.text(x0 + 9, y + h / 2 - 4, str(k + 1), 11 if big else 9, rgb=S().accent, bold=True)
    return top - n * (h + 6)


def prompt_box(c, x0, x1, top, bottom, title, prompt=None, icon_kind=None, kind="lines"):
    """A card with a title, an optional grey prompt and lines (or dots)."""
    y = card(c.p, x0, bottom, x1 - x0, top - bottom, title, icon_kind)
    if prompt:
        c.p.text(x0 + 10, y - 4, prompt, 8, rgb=S().soft)
        y -= 16
    if kind == "lines":
        lines(c.p, x0 + 10, x1 - 10, y - 18, bottom + 10, 24)
    elif kind == "checks":
        checks(c.p, x0 + 10, x1 - 10, y - 16, bottom + 12, 24)
    elif kind == "dots":
        dots(c.p, x0 + 12, x1 - 12, y - 8, bottom + 10, 14)


def tracker_row(c, x0, x1, y, name, n, icon_kind=None, kind="boxes"):
    """A row to tick [n] times: name on the left, boxes or circles after."""
    if icon_kind:
        icon(c.p, icon_kind, x0 + 6, y + 4, 11, S().accent)
    c.p.text(x0 + (18 if icon_kind else 0), y, name, 9, rgb=S().ink, bold=True)
    bx = x0 + 96
    size = min(14, (x1 - bx) / n - 4)
    for k in range(n):
        x = bx + k * (size + 4)
        if kind == "circles":
            circle(c.p, x + size / 2, y + 3, size / 2, S().soft, fill=False, width=0.9)
        else:
            rrect(c.p, x, y - 3, size, size, 3, stroke=S().soft, width=0.9)


def rating(c, x0, y, name, n=5, words=None, icon_kind=None):
    if icon_kind:
        icon(c.p, icon_kind, x0 + 6, y + 4, 11, S().accent)
    c.p.text(x0 + (18 if icon_kind else 0), y, name, 9, rgb=S().ink, bold=True)
    scale(c.p, x0 + 96, y + 3, n, 12, words)


def table(c, x0, x1, top, bottom, heads, fracs=None, row_h=26):
    """A table with headings; [fracs] are column widths (fractions)."""
    fracs = fracs or [1 / len(heads)] * len(heads)
    rrect(c.p, x0, top - 22, x1 - x0, 22, 6, fill=S().tab)
    x = x0
    edges = []
    for head, f in zip(heads, fracs):
        w = (x1 - x0) * f
        c.p.text(x + 8, top - 15, head, 8.5, rgb=S().accent, bold=True)
        edges.append(x)
        x += w
    y = top - 22
    while y - row_h >= bottom - 0.5:
        y -= row_h
        c.p.line(x0, y, x1, y)
    for e in edges[1:]:
        c.p.line(e, top - 22, e, y, rgb=tint(S().rule, 0.3), width=0.6)
    return y


def week_strip(c, x0, x1, top, h):
    """The seven days of week [c.w] as linked boxes in a row; returns the
    bottom."""
    days = c.book.week_day_pages(c.w)
    cols = columns(x0, x1, 7, 6)
    for (a, b), (name, sub, page) in zip(cols, days):
        rrect(c.p, a, top - h, b - a, h, 6, stroke=S().rule)
        rrect(c.p, a, top - 20, b - a, 20, 6, fill=S().tab)
        c.p.text(a + 6, top - 14, name[:3], 8.5, rgb=S().accent, bold=True)
        if sub:
            c.p.text(b - 6, top - 14, sub, 7.5, rgb=S().soft, right=True)
        if page is not None:
            c.p.link(a, top - 22, b - a, 22, page)
    return top - h


def mini_cal(c, x0, x1, top, today=None):
    """This page's month, small, with linked dates and weeks."""
    w = x1 - x0
    return c.book.mini_month(c.p, c.m, x0, top, w, 12, 7.5, today=today, week_links=True)


# Year pages

def year_goals(c):
    areas = [("Health & body", "heart"), ("Mind", "cloud"), ("Work & study", "briefcase"),
             ("Money", "coin"), ("People", "people"), ("Fun & growth", "star")]
    n_cols = 3 if c.landscape else 2
    cols = columns(c.left, c.right, n_cols, 12)
    n_rows = len(areas) // n_cols
    rws = rows(c.top, c.bottom, [1] * n_rows, 12)
    for k, (name, ic) in enumerate(areas):
        (x0, x1), (t, b) = cols[k % n_cols], rws[k // n_cols]
        prompt_box(c, x0, x1, t, b, name, "What would make this a great year?", ic, "checks")


def year_pixels(c, what="mood"):
    """A square for every day, coloured by [what]; each opens its day."""
    book = c.book
    name_w = 20
    cw = (c.right - c.left - name_w) / book.n
    top, bottom = c.top, c.bottom + 30
    rh = (top - 16 - bottom) / 31
    for m in range(book.n):
        x = c.left + name_w + m * cw
        c.p.text(x + cw / 2, top - 10, book.month_name(m, True), 8, rgb=S().accent, bold=True, center=True)
        c.p.link(x, top - 16, cw, 20, book.month_page[m][0])
    for n in range(1, 32):
        y = top - 16 - n * rh
        c.p.text(c.left + name_w - 5, y + rh / 2 - 3, str(n), 6.5, rgb=S().soft, right=True)
        for m in range(book.n):
            i = _day_of_month(book, m, n)
            if i is None:
                continue
            x = c.left + name_w + m * cw
            rrect(c.p, x + 1.5, y + 1, cw - 3, rh - 2, 2, stroke=S().rule, width=0.6)
            c.p.link(x, y, cw, rh, book.day_page[i][0])
    keys = ["Great", "Good", "Okay", "Low", "Hard"] if what == "mood" else ["", "", "", "", ""]
    kw = (c.right - c.left - 40) / 5
    label(c.p, c.left, c.bottom + 6, "Key", 9)
    for k, word in enumerate(keys):
        x = c.left + 40 + k * kw
        rrect(c.p, x, c.bottom + 2, 14, 14, 3, stroke=S().soft)
        c.p.text(x + 20, c.bottom + 6, word, 8, rgb=S().soft)
        c.p.line(x + 20 + text_width(word, 8) + 4, c.bottom + 3, x + kw - 12, c.bottom + 3)


def _day_of_month(book, m, n):
    if book.dated:
        first = book.months[m]
        if n > calendar.monthrange(first.year, first.month)[1]:
            return None
        return book.day_index.get(dt.date(first.year, first.month, n))
    return m * 31 + n - 1


def vision_board(c):
    """Six frames to paste photos or stickers in, with captions."""
    n_cols = 3
    cols = columns(c.left, c.right, n_cols, 12)
    rws = rows(c.top, c.bottom, [1, 1], 12)
    for k in range(6):
        (x0, x1), (t, b) = cols[k % 3], rws[k // 3]
        rrect(c.p, x0, b + 26, x1 - x0, t - b - 26, 8, stroke=S().rule)
        dots(c.p, x0 + 10, x1 - 10, t - 10, b + 34, 16)
        c.p.line(x0, b + 8, x1, b + 8)


def routines(c):
    cols = columns(c.left, c.right, 2, 16)
    for (x0, x1), (name, ic, hint) in zip(cols, [("Morning routine", "sun", "Start small: 3-5 steps."),
                                                 ("Evening wind-down", "moon", "Screens off, prep tomorrow.")]):
        prompt_box(c, x0, x1, c.top, c.bottom, name, hint, ic, "checks")


def rewards_menu(c):
    """Rewards for small, medium and big wins, ADHD-style."""
    cols = columns(c.left, c.right, 3, 12)
    for (x0, x1), (name, hint) in zip(cols, [("Small wins", "5 minutes: a song, a snack"),
                                             ("Medium wins", "An episode, a walk, a coffee out"),
                                             ("Big wins", "A day trip, something new")]):
        prompt_box(c, x0, x1, c.top, c.bottom, name, hint, "gift", "checks")


# Month pages

def month_calendar(c):
    """The month: a big grid; dates open days, the W column opens weeks."""
    book, p = c.book, c.p
    side = c.landscape
    right = c.right - (170 if side else 0)
    bottom = c.bottom if side else c.bottom + 150
    grid_left = c.left + 30
    cw = (right - grid_left) / 7
    top = c.top + 4
    for k, name in enumerate(book.weekday_names()):
        p.text(grid_left + k * cw + cw / 2, top - 10, name[:3], 8.5, rgb=S().soft, bold=True, center=True)
    weeks = book.month_weeks(c.m)
    rh = (top - 18 - bottom) / len(weeks)
    for r, row in enumerate(weeks):
        y = top - 18 - (r + 1) * rh
        wi = book.row_week(c.m, r, row)
        if wi is not None:
            rrect(p, c.left, y + 2, 26, rh - 4, 6, fill=S().tab)
            p.text(c.left + 13, y + rh / 2 - 3, f"W{wi + 1}", 8, rgb=S().accent, bold=True, center=True)
            p.link(c.left, y, 26, rh, book.week_page[wi][0])
        for k, cell in enumerate(row):
            x = grid_left + k * cw
            p.rect(x, y, cw, rh, stroke=S().rule)
            i = book.cell_day(c.m, cell)
            if book.dated:
                inside = i is not None
                p.text(x + 6, y + rh - 14, str(cell.day), 10, rgb=S().ink if inside else S().rule, bold=inside)
            elif cell <= 31:
                p.text(x + 6, y + rh - 14, str(cell), 10, rgb=S().soft)
            if i is not None:
                circle(p, x + cw - 7, y + rh - 10, 1.8, tint(S().accent, 0.3))
                p.link(x, y, cw, rh, book.day_page[i][0])
    if side:
        x0 = right + 16
        t, b = rows(c.top, c.bottom, [1, 1.4], 12)
        prompt_box(c, x0, c.right, *t, "Focus", None, "target", "checks")
        prompt_box(c, x0, c.right, *b, "Notes", None, None, "lines")
    else:
        cols = columns(c.left, c.right, 2, 16)
        prompt_box(c, *cols[0], c.bottom + 136, c.bottom, "Focus", None, "target", "checks")
        prompt_box(c, *cols[1], c.bottom + 136, c.bottom, "Notes", None, None, "lines")


def month_habits(c):
    """A habit per row, a box per day; each day number opens that day."""
    book, p = c.book, c.p
    if book.dated:
        first = book.months[c.m]
        count = calendar.monthrange(first.year, first.month)[1]
    else:
        count = 31
    name_w = 110
    cw = (c.right - c.left - name_w) / count
    top = c.top
    for n in range(1, count + 1):
        x = c.left + name_w + (n - 1) * cw
        p.text(x + cw / 2, top - 8, str(n), 6.5, rgb=S().accent, bold=True, center=True)
        if book.dated:
            d = dt.date(first.year, first.month, n)
            p.text(x + cw / 2, top - 17, DAY_NAMES[d.weekday()][0], 5.5, rgb=S().soft, center=True)
        i = _day_of_month(book, c.m, n)
        if i is not None:
            p.link(x, top - 20, cw, 24, book.day_page[i][0])
    label(p, c.left, top - 12, "Habit", 9, "check")
    y = top - 26
    size = min(cw - 3, 13)
    while y - 26 >= c.bottom:
        y -= 26
        p.line(c.left, y + 2, c.left + name_w - 10, y + 2)
        for n in range(count):
            x = c.left + name_w + n * cw + (cw - size) / 2
            rrect(p, x, y + 3, size, size, 2.5, stroke=S().rule, width=0.6)


def month_review(c, prompts=None):
    prompts = prompts or [("Wins", "star", "What went well? Big or small."),
                          ("What worked", "check", "Strategies, tools, times of day."),
                          ("What got in the way", "cloud", "No blame, just patterns."),
                          ("Energy & mood", "bolt", "When did I feel best?"),
                          ("Next month", "target", "One thing to try."),
                          ("Grateful for", "heart", None)]
    n_cols = 3 if c.landscape else 2
    cols = columns(c.left, c.right, n_cols, 12)
    n_rows = (len(prompts) + n_cols - 1) // n_cols
    rws = rows(c.top, c.bottom, [1] * n_rows, 12)
    for k, (name, ic, hint) in enumerate(prompts):
        prompt_box(c, *cols[k % n_cols], *rws[k // n_cols], name, hint, ic)


def month_goals(c):
    cols = columns(c.left, c.right, 2, 16)
    t1, t2 = rows(c.top, c.bottom, [1, 1], 12)
    prompt_box(c, *cols[0], *t1, "Goals this month", None, "target", "checks")
    prompt_box(c, *cols[1], *t1, "Action steps", None, "list", "checks")
    prompt_box(c, *cols[0], *t2, "Important dates", None, "calendar")
    prompt_box(c, *cols[1], *t2, "To remember", None, None)


def month_mental_health(c):
    """Mood and anxiety per day, plus what helped: a monthly check-in."""
    p, book = c.p, c.book
    top = c.top
    label(p, c.left, top - 12, "Mood & anxiety by day", 10, "heart")
    count = 31
    if book.dated:
        first = book.months[c.m]
        count = calendar.monthrange(first.year, first.month)[1]
    cw = (c.right - c.left - 70) / count
    for r, name in enumerate(["Mood", "Anxiety", "Sleep", "Energy"]):
        y = top - 44 - r * 22
        p.text(c.left, y + 3, name, 8.5, rgb=S().ink, bold=True)
        for n in range(count):
            x = c.left + 70 + n * cw
            rrect(p, x + 1, y, cw - 2, 14, 2, stroke=S().rule, width=0.6)
            if r == 0:
                p.text(x + cw / 2, top - 26, str(n + 1), 6, rgb=S().accent, bold=True, center=True)
                i = _day_of_month(book, c.m, n + 1)
                if i is not None:
                    p.link(x, top - 30, cw, 14, book.day_page[i][0])
    p.text(c.left + 70, top - 134, "Colour 1-5: 1 = low, 5 = high.", 7.5, rgb=S().soft)
    n_cols = 3 if c.landscape else 2
    cols = columns(c.left, c.right, n_cols, 12)
    items = [("What helped", "leaf", None), ("Triggers I noticed", "bolt", None),
             ("Self-care I did", "heart", None), ("Questions for therapy", "cloud", None),
             ("Small wins", "star", None), ("Next month I need", "target", None)]
    items = items[:n_cols * 2]
    rws = rows(top - 146, c.bottom, [1, 1], 12)
    for k, (name, ic, hint) in enumerate(items):
        prompt_box(c, *cols[k % n_cols], *rws[k // n_cols], name, hint, ic)


def month_budget(c):
    cols = columns(c.left, c.right, 2, 16)
    t1, t2 = rows(c.top, c.bottom, [1, 1.3], 12)
    x0, x1 = cols[0]
    card(c.p, x0, t1[1], x1 - x0, t1[0] - t1[1], "Income", "coin")
    table(c, x0 + 8, x1 - 8, t1[0] - 30, t1[1] + 8, ["Source", "Amount"], [0.65, 0.35])
    x0, x1 = cols[1]
    card(c.p, x0, t1[1], x1 - x0, t1[0] - t1[1], "Bills", "calendar")
    table(c, x0 + 8, x1 - 8, t1[0] - 30, t1[1] + 8, ["Bill", "Due", "Paid"], [0.55, 0.25, 0.2])
    x0, x1 = c.left, c.right
    card(c.p, x0, t2[1], x1 - x0, t2[0] - t2[1], "Spending", "chart")
    table(c, x0 + 8, x1 - 8, t2[0] - 30, t2[1] + 8, ["Date", "What", "Category", "Amount"],
          [0.15, 0.45, 0.22, 0.18])


def content_calendar(c):
    """A month of posts: channel, idea and status per day."""
    table(c, c.left, c.right, c.top, c.bottom, ["Date", "Channel", "Idea / hook", "Status"],
          [0.12, 0.18, 0.55, 0.15], 24)


def income_expenses(c):
    cols = columns(c.left, c.right, 2, 16)
    for (x0, x1), name in zip(cols, ["Income", "Expenses"]):
        card(c.p, x0, c.bottom, x1 - x0, c.top - c.bottom, name, "coin")
        table(c, x0 + 8, x1 - 8, c.top - 30, c.bottom + 40, ["Date", "Description", "Amount"],
              [0.2, 0.55, 0.25])
        c.p.text(x0 + 12, c.bottom + 16, "Total", 9, rgb=S().accent, bold=True)
        c.p.line(x0 + 50, c.bottom + 14, x1 - 12, c.bottom + 14)


def milestones(c):
    cols = columns(c.left, c.right, 2, 16)
    prompt_box(c, *cols[0], c.top, c.bottom, "Milestones this month", "Linked to your goal dashboards.",
               "target", "checks")
    t1, t2 = rows(c.top, c.bottom, [1, 1], 12)
    prompt_box(c, *cols[1], *t1, "Progress", None, "chart")
    prompt_box(c, *cols[1], *t2, "Next steps", None, "list", "checks")


def wins(c):
    n_cols = 3 if c.landscape else 2
    cols = columns(c.left, c.right, n_cols, 12)
    rws = rows(c.top, c.bottom, [1, 1, 1] if not c.landscape else [1, 1], 12)
    k = 0
    for t, b in rws:
        for x0, x1 in cols:
            rrect(c.p, x0, b, x1 - x0, t - b, 10, stroke=S().rule)
            icon(c.p, "star", x0 + 16, t - 16, 12, tint(S().accent, 0.3))
            lines(c.p, x0 + 12, x1 - 12, t - 40, b + 12, 24)
            k += 1


# Week pages

def week_plan(c, top3=True):
    """The week's days as linked boxes, with priorities and a focus."""
    p = c.p
    if c.landscape:
        side = 180
        days = c.book.week_day_pages(c.w)
        grid_r = c.right - side - 14
        cols = columns(c.left, grid_r, 4, 8)
        rws = rows(c.top, c.bottom, [1, 1], 8)
        cells = [(cols[k % 4], rws[k // 4]) for k in range(8)]
        for k, ((x0, x1), (t, b)) in enumerate(cells):
            rrect(p, x0, b, x1 - x0, t - b, 8, stroke=S().rule)
            if k < 7:
                name, sub, page = days[k]
                rrect(p, x0, t - 22, x1 - x0, 22, 8, fill=S().tab)
                p.text(x0 + 8, t - 15, name, 9, rgb=S().accent, bold=True)
                if sub:
                    p.text(x1 - 18, t - 15, sub, 8, rgb=S().soft, right=True)
                if page is not None:
                    chevron(p, x1 - 9, t - 11.5, 6, S().accent)
                    p.link(x0, t - 24, x1 - x0, 24, page)
                checks(p, x0 + 8, x1 - 8, t - 40, b + 10, 24)
            else:
                label(p, x0 + 8, t - 16, "Notes", 9)
                lines(p, x0 + 8, x1 - 8, t - 34, b + 10, 24)
        x0 = c.right - side
        t1, t2, t3 = rows(c.top, c.bottom, [1.1, 0.8, 1], 10)
        prompt_box(c, x0, c.right, *t1, "Top 3 priorities", None, "target", "checks")
        prompt_box(c, x0, c.right, *t2, "One focus", "If only one thing gets done...", "star")
        mini_cal(c, x0 + 4, c.right - 4, t3[0] - 6, None)
    else:
        bottom = week_strip_tall(c)
        cols = columns(c.left, c.right, 3, 10)
        prompt_box(c, *cols[0], bottom - 12, c.bottom, "Top 3 priorities", None, "target", "checks")
        prompt_box(c, *cols[1], bottom - 12, c.bottom, "One focus", None, "star")
        x0, x1 = cols[2]
        mini_cal(c, x0, x1, bottom - 18)


def week_strip_tall(c):
    """Portrait: seven linked day rows down the page; returns the bottom."""
    p = c.p
    days = c.book.week_day_pages(c.w)
    bottom = c.bottom + 150
    rws = rows(c.top, bottom, [1] * 7, 6)
    for (name, sub, page), (t, b) in zip(days, rws):
        rrect(p, c.left, b, c.right - c.left, t - b, 8, stroke=S().rule)
        rrect(p, c.left, b, 70, t - b, 8, fill=S().tab)
        p.text(c.left + 8, t - 16, name[:3], 10, rgb=S().accent, bold=True)
        if sub:
            p.text(c.left + 8, t - 30, sub, 8, rgb=S().soft)
        if page is not None:
            chevron(p, c.left + 60, t - 12, 6, S().accent)
            p.link(c.left, b, 70, t - b, page)
        lines(p, c.left + 80, c.right - 10, t - 22, b + 6, 24)
    return bottom


def week_review(c):
    month_review(c, [("Wins this week", "star", None), ("What drained me", "bolt", None),
                     ("What helped", "leaf", None), ("Carry over", "list", None),
                     ("Next week's focus", "target", None), ("Grateful for", "heart", None)])


def meals_movement(c):
    """Meals and movement for each day of the week."""
    p = c.p
    days = c.book.week_day_pages(c.w)
    heads = ["Day", "Breakfast", "Lunch", "Dinner", "Snacks", "Movement", "Water"]
    fr = [0.1, 0.17, 0.17, 0.17, 0.13, 0.16, 0.1]
    bottom = c.bottom + 110
    y = table(c, c.left, c.right, c.top, bottom, heads, fr, (c.top - 22 - bottom) / 7)
    rh = (c.top - 22 - bottom) / 7
    for k, (name, _, page) in enumerate(days):
        ty = c.top - 22 - (k + 1) * rh
        p.text(c.left + 8, ty + rh / 2 - 3, name[:3], 9, rgb=S().accent, bold=True)
        if page is not None:
            p.link(c.left, ty, (c.right - c.left) * fr[0], rh, page)
    cols = columns(c.left, c.right, 2, 16)
    prompt_box(c, *cols[0], bottom - 10, c.bottom, "Groceries", None, "list", "checks")
    prompt_box(c, *cols[1], bottom - 10, c.bottom, "Prep ahead", None, "check", "checks")


# Day pages

def day_focus(c):
    """ADHD-friendly day: time blocks, Top 3, one thing, to-do and a
    reward, with room to write."""
    p = c.p
    n = 2 if c.landscape else 2
    (a0, a1), (b0, b1) = columns(c.left, c.right, n, 18)
    time_blocks(c, a0, a1, c.top, c.bottom, 7, 21 if c.landscape else 22)
    t1, t2, t3, t4 = rows(c.top, c.bottom, [0.75, 1.15, 1.6, 0.6], 10)
    prompt_box(c, b0, b1, *t1, "The one thing", "If only this gets done, today counts.", "star")
    y = card(p, b0, t2[1], b1 - b0, t2[0] - t2[1], "Top 3", "target")
    h = (y - t2[1] - 10 - 12) / 3
    for k in range(3):
        ty = y - (k + 1) * h - k * 6 + 2
        circle(p, b0 + 18, ty + h / 2, 7, S().accent, fill=False, width=1.1)
        p.line(b0 + 32, ty + h / 2 - 7, b1 - 10, ty + h / 2 - 7)
    prompt_box(c, b0, b1, *t3, "To-do", None, "list", "checks")
    prompt_box(c, b0, b1, *t4, "Reward", None, "gift")


def day_checkin(c):
    """How today feels: energy, mood, body, and a place to empty your head."""
    p = c.p
    if c.landscape:
        (a0, a1), (b0, b1) = columns(c.left, c.right, 2, 18)
    else:
        a0, a1 = b0, b1 = c.left, c.right
    t_scales = c.top
    h_scales = 172
    y = card(p, a0, t_scales - h_scales, a1 - a0, h_scales, "How I'm doing", "bolt")
    rating(c, a0 + 10, y - 10, "Energy", 5, None, "bolt")
    rating(c, a0 + 10, y - 34, "Mood", 5, None, "heart")
    rating(c, a0 + 10, y - 58, "Focus", 5, None, "target")
    tracker_row(c, a0 + 10, a1 - 10, y - 82, "Water", 8, "drop", "circles")
    tracker_row(c, a0 + 10, a1 - 10, y - 106, "Sleep (hrs)", 10, "moon")
    tracker_row(c, a0 + 10, a1 - 10, y - 130, "Movement", 6, "leaf")
    if c.landscape:
        t1, t2 = rows(t_scales - h_scales - 12, c.bottom, [1, 1], 12)
        prompt_box(c, a0, a1, *t1, "Morning: how am I arriving?", "Worries, hopes, one intention.", "sun")
        prompt_box(c, a0, a1, *t2, "Evening: let it go", "What went okay? What can wait?", "moon")
        prompt_box(c, b0, b1, c.top, c.bottom, "Brain dump", "Everything on your mind. Sort it later.",
                   "cloud", "dots")
    else:
        t1, t2, t3 = rows(t_scales - h_scales - 12, c.bottom, [1, 1, 1.3], 12)
        (x0, x1), (y0, y1) = columns(c.left, c.right, 2, 12)
        prompt_box(c, x0, x1, *t1, "Morning", "Worries, hopes, one intention.", "sun")
        prompt_box(c, y0, y1, *t1, "Evening", "What went okay? What can wait?", "moon")
        prompt_box(c, c.left, c.right, *t2, "Meds, meals & snacks", None, "check", "checks")
        prompt_box(c, c.left, c.right, *t3, "Brain dump", "Everything on your mind.", "cloud", "dots")


def day_journal(c):
    """Wellness day: check-in plus gratitude and a journal page."""
    p = c.p
    if c.landscape:
        (a0, a1), (b0, b1) = columns(c.left, c.right, 2, 18)
    else:
        a0, a1 = b0, b1 = c.left, c.right
    h = 148
    y = card(p, a0, c.top - h, a1 - a0, h, "Today I feel", "heart")
    words = ["Calm", "Happy", "Tired", "Anxious", "Sad", "Angry", "Hopeful", "Proud"]
    x, yy = a0 + 12, y - 10
    for wd in words:
        wdt = text_width(wd, 8.5) + 18
        if x + wdt > a1 - 10:
            x, yy = a0 + 12, yy - 22
        rrect(p, x, yy - 6, wdt, 18, 9, stroke=S().rule)
        p.text(x + 9, yy, wd, 8.5, rgb=S().soft)
        x += wdt + 6
    rating(c, a0 + 10, yy - 30, "Stress", 5, None, "bolt")
    tracker_row(c, a0 + 10, a1 - 10, yy - 54, "Water", 8, "drop", "circles")
    if c.landscape:
        t1, t2 = rows(c.top - h - 12, c.bottom, [1, 1.2], 12)
        prompt_box(c, a0, a1, *t1, "Three good things", None, "star", "checks")
        prompt_box(c, a0, a1, *t2, "Self-care today", None, "leaf", "checks")
        prompt_box(c, b0, b1, c.top, c.bottom, "Journal", "What's on my heart today?", "pencil")
    else:
        t1, t2 = rows(c.top - h - 12, c.bottom, [1, 2.2], 12)
        (x0, x1), (y0, y1) = columns(c.left, c.right, 2, 12)
        prompt_box(c, x0, x1, *t1, "Three good things", None, "star", "checks")
        prompt_box(c, y0, y1, *t1, "Self-care today", None, "leaf", "checks")
        prompt_box(c, c.left, c.right, *t2, "Journal", "What's on my heart today?", "pencil")


def day_life(c):
    """Life planner day: schedule, Top 3, to-do, gratitude, affirmation."""
    (a0, a1), (b0, b1) = columns(c.left, c.right, 2, 18)
    time_blocks(c, a0, a1, c.top, c.bottom, 6, 22, "Schedule")
    t1, t2, t3, t4 = rows(c.top, c.bottom, [0.9, 1.6, 0.8, 0.55], 10)
    prompt_box(c, b0, b1, *t1, "Top 3", None, "target", "checks")
    prompt_box(c, b0, b1, *t2, "To-do", None, "list", "checks")
    prompt_box(c, b0, b1, *t3, "Grateful for", None, "heart")
    prompt_box(c, b0, b1, *t4, "Affirmation", None, "star")


def day_goals(c):
    """Goals planner day: priorities tied to goals, schedule, notes."""
    (a0, a1), (b0, b1) = columns(c.left, c.right, 2, 18)
    time_blocks(c, a0, a1, c.top, c.bottom, 6, 22, "Schedule")
    t1, t2, t3 = rows(c.top, c.bottom, [1.2, 1.2, 1], 10)
    y = card(c.p, b0, t1[1], b1 - b0, t1[0] - t1[1], "Top 3 for my goals", "target")
    h = (y - t1[1] - 8) / 3
    for k in range(3):
        ty = y - (k + 1) * h
        c.p.text(b0 + 10, ty + h / 2, f"{k + 1}", 11, rgb=S().accent, bold=True)
        c.p.line(b0 + 26, ty + h / 2 - 2, b1 - 90, ty + h / 2 - 2)
        c.p.text(b1 - 84, ty + h / 2, "Goal #", 7.5, rgb=S().soft)
        c.p.line(b1 - 54, ty + h / 2 - 2, b1 - 10, ty + h / 2 - 2)
    prompt_box(c, b0, b1, *t2, "Other tasks", None, "list", "checks")
    prompt_box(c, b0, b1, *t3, "Notes & wins", None, "star")


def day_student(c):
    """Student day: classes, due today, study block and to-do."""
    (a0, a1), (b0, b1) = columns(c.left, c.right, 2, 18)
    t1, t2 = rows(c.top, c.bottom, [1, 1.2], 10)
    card(c.p, a0, t1[1], a1 - a0, t1[0] - t1[1], "Classes", "cap")
    table(c, a0 + 8, a1 - 8, t1[0] - 30, t1[1] + 8, ["Time", "Class", "Room"], [0.22, 0.56, 0.22])
    time_blocks(c, a0, a1, t2[0], t2[1], 15, 22, "Study blocks")
    u1, u2, u3 = rows(c.top, c.bottom, [1, 1.3, 0.9], 10)
    prompt_box(c, b0, b1, *u1, "Due today", None, "check", "checks")
    prompt_box(c, b0, b1, *u2, "To-do", None, "list", "checks")
    y = card(c.p, b0, u3[1], b1 - b0, u3[0] - u3[1], "Pomodoros", "target")
    for k in range(8):
        circle(c.p, b0 + 22 + k * 26, y - 14, 9, S().soft, fill=False, width=0.9)


def day_business(c):
    """Business day: 3 priorities, time blocks, health and habits."""
    (a0, a1), (b0, b1) = columns(c.left, c.right, 2, 18)
    time_blocks(c, a0, a1, c.top, c.bottom, 7, 20, "Time blocks")
    t1, t2, t3, t4 = rows(c.top, c.bottom, [1, 1.3, 0.75, 0.75], 10)
    prompt_box(c, b0, b1, *t1, "3 priorities", None, "target", "checks")
    prompt_box(c, b0, b1, *t2, "Calls, emails & admin", None, "briefcase", "checks")
    y = card(c.p, b0, t3[1], b1 - b0, t3[0] - t3[1], "Health & habits", "leaf")
    tracker_row(c, b0 + 10, b1 - 10, y - 12, "Water", 8, "drop", "circles")
    tracker_row(c, b0 + 10, b1 - 10, y - 34, "Habits", 6)
    prompt_box(c, b0, b1, *t4, "Grateful for", None, "heart")


# Collection pages

def brain_dump(c):
    prompt_box(c, c.left, c.right, c.top, c.bottom, "Everything on my mind",
               "Write it all out. Circle what matters; cross out what doesn't.", "cloud", "dots")


def task_breakdown(c):
    """A big task broken into small steps, with time guesses."""
    p = c.p
    label(p, c.left, c.top - 12, "Big task", 10, "target")
    p.line(c.left + 70, c.top - 14, c.right, c.top - 14)
    label(p, c.left, c.top - 40, "Why it matters", 10, "heart")
    p.line(c.left + 104, c.top - 42, c.right, c.top - 42)
    table(c, c.left, c.right, c.top - 62, c.bottom + 34, ["#", "Tiny step", "Minutes", "Done"],
          [0.07, 0.63, 0.15, 0.15], 26)
    p.text(c.left, c.bottom + 12, "Tip: if a step takes more than 25 minutes, break it in two.", 8.5,
           rgb=S().soft)


def lined_page(c):
    lines(c.p, c.left, c.right, c.top - 10, c.bottom, 26)


def dotted_page(c):
    dots(c.p, c.left, c.right, c.top - 6, c.bottom, 16)


def checklist_page(c):
    checks(c.p, c.left, c.right, c.top - 12, c.bottom + 6, 28)


def therapy_notes(c):
    p = c.p
    for k, word in enumerate(["Date", "Session #"]):
        x = c.left + k * 220
        p.text(x, c.top - 10, word, 9, rgb=S().accent, bold=True)
        p.line(x + text_width(word, 9) + 6, c.top - 12, x + 200, c.top - 12)
    top = c.top - 26
    n_cols = 2
    cols = columns(c.left, c.right, n_cols, 12)
    rws = rows(top, c.bottom, [1, 1.3, 1], 12)
    items = [("Before: what I want to talk about", "cloud"), ("How I'm feeling", "heart"),
             ("Key takeaways", "star"), ("Things to try", "check"),
             ("Homework", "pencil"), ("After: how do I feel?", "leaf")]
    for k, (name, ic) in enumerate(items):
        prompt_box(c, *cols[k % 2], *rws[k // 2], name, None, ic, "checks" if name == "Things to try" else "lines")


def anxiety_journal(c):
    cols = columns(c.left, c.right, 2, 12)
    rws = rows(c.top, c.bottom, [1, 1, 1], 12)
    items = [("What am I worried about?", "cloud"), ("How likely is it, really?", "chart"),
             ("What can I control?", "check"), ("What can I let go?", "leaf"),
             ("What would I tell a friend?", "heart"), ("One small step", "target")]
    for k, (name, ic) in enumerate(items):
        prompt_box(c, *cols[k % 2], *rws[k // 2], name, None, ic)


def self_care_menu(c):
    cols = columns(c.left, c.right, 3 if c.landscape else 2, 12)
    items = [("5 minutes", "sun"), ("30 minutes", "leaf"), ("An afternoon", "heart"),
             ("When I'm anxious", "cloud"), ("When I'm low", "moon"), ("People I can call", "people")]
    n = len(cols)
    rws = rows(c.top, c.bottom, [1] * ((len(items) + n - 1) // n), 12)
    for k, (name, ic) in enumerate(items):
        prompt_box(c, *cols[k % n], *rws[k // n], name, None, ic, "checks")


def sleep_log(c):
    table(c, c.left, c.right, c.top, c.bottom, ["Date", "Bed", "Up", "Hours", "Quality 1-5", "Notes"],
          [0.12, 0.1, 0.1, 0.1, 0.14, 0.44], 24)


def gratitude(c):
    n_cols = 2
    cols = columns(c.left, c.right, n_cols, 12)
    rws = rows(c.top, c.bottom, [1, 1, 1], 12)
    for k in range(6):
        x0, x1 = cols[k % 2]
        t, b = rws[k // 2]
        rrect(c.p, x0, b, x1 - x0, t - b, 8, stroke=S().rule)
        c.p.text(x0 + 10, t - 16, "Date", 8, rgb=S().soft, bold=True)
        c.p.line(x0 + 36, t - 18, x0 + 120, t - 18)
        icon(c.p, "heart", x1 - 16, t - 13, 11, tint(S().accent, 0.3))
        for j in range(3):
            y = t - 40 - j * 24
            if y < b + 6:
                break
            c.p.text(x0 + 10, y + 2, f"{j + 1}.", 9, rgb=S().accent, bold=True)
            c.p.line(x0 + 24, y, x1 - 10, y)


def stress_tracker(c):
    table(c, c.left, c.right, c.top, c.bottom, ["Date", "Stress 1-10", "What happened", "How I coped"],
          [0.12, 0.13, 0.4, 0.35], 26)


def goal_dashboard(c):
    """One goal: why, deadline, milestones by month, action steps, progress."""
    p = c.p
    for k, word in enumerate(["Goal", "Deadline"]):
        x = c.left + k * (c.right - c.left) * 0.62
        p.text(x, c.top - 10, word, 10, rgb=S().accent, bold=True)
        x1 = c.left + (c.right - c.left) * (0.58 if k == 0 else 1)
        p.line(x + text_width(word, 10) + 6, c.top - 12, x1, c.top - 12)
    y = c.top - 34
    label(p, c.left, y, "Progress", 9, "chart")
    seg = (c.right - c.left - 70) / 10
    for k in range(10):
        rrect(p, c.left + 70 + k * seg, y - 4, seg - 3, 14, 3, stroke=S().rule)
        p.text(c.left + 70 + k * seg + seg / 2 - 1, y - 14, f"{(k + 1) * 10}%", 6, rgb=S().soft, center=True)
    top = y - 26
    (a0, a1), (b0, b1) = columns(c.left, c.right, 2, 14)
    t1, t2 = rows(top, c.bottom, [1, 1.4], 12)
    prompt_box(c, a0, a1, *t1, "Why it matters", None, "heart")
    prompt_box(c, a0, a1, *t2, "Action steps", None, "list", "checks")
    y = card(p, b0, c.bottom, b1 - b0, top - c.bottom, "Milestones by month", "calendar")
    rh = (y - c.bottom - 8) / c.book.n
    for m in range(c.book.n):
        ty = y - (m + 1) * rh
        name = c.book.month_name(m, True)
        p.text(b0 + 10, ty + rh / 2 - 3, name, 8.5, rgb=S().accent, bold=True)
        p.link(b0 + 6, ty, 40, rh, c.book.month_page[m][0])
        p.line(b0 + 46, ty + 3, b1 - 10, ty + 3)


def project_dashboard(c):
    p = c.p
    fields = [("Project", 0.5), ("Start", 0.22), ("Due", 0.22)]
    x = c.left
    for word, f in fields:
        w = (c.right - c.left) * f
        p.text(x, c.top - 10, word, 10, rgb=S().accent, bold=True)
        p.line(x + text_width(word, 10) + 6, c.top - 12, x + w - 12, c.top - 12)
        x += w + (c.right - c.left) * 0.02
    top = c.top - 30
    (a0, a1), (b0, b1) = columns(c.left, c.right, 2, 14)
    t1, t2 = rows(top, c.bottom, [0.8, 1.2], 12)
    prompt_box(c, a0, a1, *t1, "Outcome", "What does done look like?", "target")
    prompt_box(c, a0, a1, *t2, "Notes & links", None, "pencil")
    card(p, b0, c.bottom, b1 - b0, top - c.bottom, "Tasks", "list")
    table(c, b0 + 8, b1 - 8, top - 30, c.bottom + 8, ["Task", "Due", "Done"], [0.62, 0.22, 0.16], 24)


def goal_roadmap(c):
    """Goal clarity: from a dream to this week's step."""
    steps = [("Dream", "Where do I want to be in 3 years?", "star"),
             ("This year", "What would make this year a success?", "target"),
             ("This quarter", "Which milestones get me there?", "chart"),
             ("This month", "What's the next milestone?", "calendar"),
             ("This week", "One step I can take now.", "check")]
    p = c.p
    rws = rows(c.top, c.bottom, [1] * len(steps), 8)
    for k, ((t, b), (name, hint, ic)) in enumerate(zip(rws, steps)):
        indent = k * (18 if c.landscape else 10)
        rrect(p, c.left + indent, b, c.right - c.left - indent, t - b, 10, fill=S().tab if k % 2 else None,
              stroke=S().rule)
        label(p, c.left + indent + 10, t - 18, name, 10, ic)
        p.text(c.left + indent + 130, t - 18, hint, 8.5, rgb=S().soft)
        lines(p, c.left + indent + 10, c.right - 10, t - 36, b + 8, 24)


def quarter_review(c):
    month_review(c, [("Wins", "star", None), ("Goals on track", "check", None),
                     ("Goals to rethink", "cloud", None), ("Lessons", "leaf", None),
                     ("Next quarter's focus", "target", None), ("Celebrate", "gift", None)])


def course_dashboard(c):
    p = c.p
    fields = ["Course", "Teacher", "Room", "Times"]
    cols = columns(c.left, c.right, 2, 20)
    for k, word in enumerate(fields):
        x0, x1 = cols[k % 2]
        y = c.top - 10 - (k // 2) * 22
        p.text(x0, y, word, 9.5, rgb=S().accent, bold=True)
        p.line(x0 + text_width(word, 9.5) + 6, y - 2, x1, y - 2)
    top = c.top - 56
    (a0, a1), (b0, b1) = cols
    card(p, a0, c.bottom, a1 - a0, top - c.bottom, "Assignments & exams", "check")
    table(c, a0 + 8, a1 - 8, top - 30, c.bottom + 8, ["What", "Due", "Grade"], [0.6, 0.2, 0.2], 24)
    t1, t2 = rows(top, c.bottom, [1, 1], 12)
    prompt_box(c, b0, b1, *t1, "Grading & syllabus notes", None, "book")
    prompt_box(c, b0, b1, *t2, "Questions for office hours", None, "cloud")


def assignment_tracker(c):
    table(c, c.left, c.right, c.top, c.bottom, ["Course", "Assignment", "Due", "Status", "Grade"],
          [0.18, 0.44, 0.13, 0.13, 0.12], 24)


def exam_planner(c):
    cols = columns(c.left, c.right, 2, 14)
    rws = rows(c.top, c.bottom, [1, 1], 12)
    for k in range(4):
        x0, x1 = cols[k % 2]
        t, b = rws[k // 2]
        y = card(c.p, x0, b, x1 - x0, t - b, f"Exam {k + 1}", "cap")
        for j, word in enumerate(["Course", "Date"]):
            c.p.text(x0 + 10 + j * 140, y - 4, word, 8.5, rgb=S().soft, bold=True)
            c.p.line(x0 + 50 + j * 140, y - 6, x0 + 130 + j * 140, y - 6)
        checks(c.p, x0 + 10, x1 - 10, y - 30, b + 12, 24)


def pomodoro(c):
    p = c.p
    table(c, c.left, c.right, c.top, c.bottom + 40, ["Date", "Task", "Pomodoros (25 min)"], [0.13, 0.45, 0.42], 26)
    p.text(c.left, c.bottom + 16, "25 minutes on, 5 off. After four, take 20.", 8.5, rgb=S().soft)


def gpa_tracker(c):
    table(c, c.left, c.right, c.top, c.bottom, ["Course", "Credits", "Grade", "Points", "Term"],
          [0.4, 0.13, 0.13, 0.13, 0.21], 24)


def reading_log(c):
    table(c, c.left, c.right, c.top, c.bottom, ["Title", "Author", "Started", "Finished", "Rating"],
          [0.36, 0.26, 0.13, 0.13, 0.12], 26)


def class_schedule(c):
    p = c.p
    days = ["Mon", "Tue", "Wed", "Thu", "Fri"]
    cols = columns(c.left + 40, c.right, 5, 4)
    for (x0, x1), d in zip(cols, days):
        rrect(p, x0, c.top - 22, x1 - x0, 22, 6, fill=S().tab)
        p.text((x0 + x1) / 2, c.top - 15, d, 9, rgb=S().accent, bold=True, center=True)
    hours = list(range(8, 19))
    rh = (c.top - 30 - c.bottom) / len(hours)
    for k, h in enumerate(hours):
        y = c.top - 30 - k * rh
        p.text(c.left, y - 12, _hour(h), 8, rgb=S().soft, bold=True)
        p.line(c.left + 40, y, c.right, y)
    p.line(c.left + 40, c.bottom, c.right, c.bottom)


def year_review(c):
    month_review(c, [("Proudest moments", "star", None), ("Biggest lessons", "leaf", None),
                     ("What I'll leave behind", "cloud", None), ("Revenue & numbers", "chart", None),
                     ("Best clients & projects", "people", None), ("Word for next year", "target", None)])


def business_strategy(c):
    month_review(c, [("Mission", "target", "Why does the business exist?"),
                     ("Ideal client", "people", "Who, their problem, where they are."),
                     ("Offers & pricing", "coin", None), ("Brand voice", "pencil", "Three words."),
                     ("Strengths & gaps", "chart", None), ("This year's big moves", "star", None)])


def marketing_plan(c):
    cols = columns(c.left, c.right, 2, 14)
    t1, t2 = rows(c.top, c.bottom, [1, 1.2], 12)
    prompt_box(c, *cols[0], *t1, "Channels", "Where my clients are.", "people", "checks")
    prompt_box(c, *cols[1], *t1, "Content pillars", None, "list", "checks")
    card(c.p, c.left, t2[1], c.right - c.left, t2[0] - t2[1], "Campaigns", "chart")
    table(c, c.left + 8, c.right - 8, t2[0] - 30, t2[1] + 8, ["Campaign", "Launch", "Goal", "Result"],
          [0.4, 0.15, 0.25, 0.2], 24)


def client_card(c):
    p = c.p
    cols = columns(c.left, c.right, 2, 20)
    for k, word in enumerate(["Client", "Contact", "Email", "Phone", "Project", "Rate"]):
        x0, x1 = cols[k % 2]
        y = c.top - 10 - (k // 2) * 24
        p.text(x0, y, word, 9.5, rgb=S().accent, bold=True)
        p.line(x0 + text_width(word, 9.5) + 6, y - 2, x1, y - 2)
    top = c.top - 84
    t1, t2 = rows(top, c.bottom, [1, 1], 12)
    card(p, c.left, t1[1], c.right - c.left, t1[0] - t1[1], "Invoices", "coin")
    table(c, c.left + 8, c.right - 8, t1[0] - 30, t1[1] + 8, ["Invoice", "Sent", "Amount", "Paid"],
          [0.3, 0.2, 0.3, 0.2], 24)
    prompt_box(c, c.left, c.right, *t2, "Notes", None, "pencil")


def finance_overview(c):
    """Income, spending and saving for every month of the year."""
    book = c.book
    heads = ["Month", "Income", "Spending", "Saved", "Notes"]
    fr = [0.14, 0.18, 0.18, 0.18, 0.32]
    rh = (c.top - 22 - c.bottom) / (book.n + 1)
    table(c, c.left, c.right, c.top, c.bottom, heads, fr, rh)
    for m in range(book.n):
        y = c.top - 22 - (m + 1) * rh
        c.p.text(c.left + 8, y + rh / 2 - 3, book.month_name(m, True), 9, rgb=S().accent, bold=True)
        c.p.link(c.left, y, (c.right - c.left) * fr[0], rh, book.month_page[m][0])
    c.p.text(c.left + 8, c.bottom + rh / 2 - 3, "Total", 9, rgb=S().accent, bold=True)


def savings_goals(c):
    cols = columns(c.left, c.right, 2, 14)
    rws = rows(c.top, c.bottom, [1, 1], 12)
    for k in range(4):
        x0, x1 = cols[k % 2]
        t, b = rws[k // 2]
        y = card(c.p, x0, b, x1 - x0, t - b, f"Saving for", "coin")
        c.p.line(x0 + 90, t - 20, x1 - 10, t - 20)
        n = 20
        cw = (x1 - x0 - 20) / 10
        for j in range(n):
            cx = x0 + 10 + (j % 10) * cw + cw / 2
            cy = y - 18 - (j // 10) * (cw + 2)
            circle(c.p, cx, cy, min(cw / 2 - 2, 9), S().soft, fill=False, width=0.9)
        c.p.text(x0 + 10, b + 12, "Each circle = $ ______", 8, rgb=S().soft)


def debt_payoff(c):
    table(c, c.left, c.right, c.top, c.bottom, ["Debt", "Balance", "Rate", "Minimum", "Paid off by"],
          [0.32, 0.17, 0.12, 0.17, 0.22], 26)


def bills_tracker(c):
    book = c.book
    heads = ["Bill", "Due"] + [book.month_name(m, True) for m in range(book.n)]
    fr = [0.2, 0.08] + [0.72 / book.n] * book.n
    table(c, c.left, c.right, c.top, c.bottom, heads, fr, 24)


def subscriptions(c):
    table(c, c.left, c.right, c.top, c.bottom, ["Service", "Cost", "Renews", "Keep?"],
          [0.45, 0.18, 0.2, 0.17], 26)


def wishlist(c):
    table(c, c.left, c.right, c.top, c.bottom, ["Item", "Where", "Price", "Bought"],
          [0.45, 0.25, 0.15, 0.15], 26)


def cleaning_schedule(c):
    cols = columns(c.left, c.right, 4 if c.landscape else 2, 10)
    items = [("Daily", "check"), ("Weekly", "calendar"), ("Monthly", "star"), ("Seasonal", "leaf")]
    n = len(cols)
    rws = rows(c.top, c.bottom, [1] * (4 // n), 12)
    for k, (name, ic) in enumerate(items):
        prompt_box(c, *cols[k % n], *rws[k // n], name, None, ic, "checks")


def meal_plan(c):
    cols = columns(c.left, c.right, 2, 14)
    t1, t2 = rows(c.top, c.bottom, [1.2, 1], 12)
    card(c.p, c.left, t1[1], c.right - c.left, t1[0] - t1[1], "Favourite meals", "heart")
    table(c, c.left + 8, c.right - 8, t1[0] - 30, t1[1] + 8, ["Meal", "Ingredients", "Time"],
          [0.3, 0.55, 0.15], 24)
    prompt_box(c, *cols[0], *t2, "Fitness goals", None, "target", "checks")
    prompt_box(c, *cols[1], *t2, "Workout ideas", None, "leaf", "checks")


def trip_planner(c):
    p = c.p
    for k, word in enumerate(["Destination", "Dates"]):
        x = c.left + k * 300
        p.text(x, c.top - 10, word, 9.5, rgb=S().accent, bold=True)
        p.line(x + text_width(word, 9.5) + 6, c.top - 12, x + 270, c.top - 12)
    top = c.top - 28
    cols = columns(c.left, c.right, 3 if c.landscape else 2, 12)
    items = [("Packing list", "check", "checks"), ("Itinerary", "calendar", "lines"),
             ("Bookings", "plane", "lines"), ("Budget", "coin", "lines"),
             ("To see & eat", "star", "checks"), ("Notes", "pencil", "lines")]
    n = len(cols)
    rws = rows(top, c.bottom, [1] * ((len(items) + n - 1) // n), 12)
    for k, (name, ic, kind) in enumerate(items):
        prompt_box(c, *cols[k % n], *rws[k // n], name, None, ic, kind)

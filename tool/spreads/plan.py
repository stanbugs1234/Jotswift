"""Planning spreads: the week, the month, the year at a glance, yearly
goals, a vision board, the day and a horizontal week. All undated: blanks
for the month, week and day."""

from spreads.kit import *  # noqa: F401,F403

DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def _fill_in(p, x, y, label):
    """A small "LABEL ______" blank."""
    caps(p, x, y, label, 6.5, rgb=S().soft)
    p.line(x + mp.text_width(label.upper(), 6.5) + 4, y - 1, x + mp.text_width(label.upper(), 6.5) + 64, y - 1,
           rgb=S().rule, width=0.6)


def week(sp, n=1):
    """The dense weekly spread: calendar, priorities and lists on the left,
    the days across both pages, to-do and habits below, notes on the
    right."""
    p = sp.page
    lx0, lx1 = sp.left
    rx0, rx1 = sp.right
    _fill_in(p, lx0 + 160, TOP + 10, "Week of")
    low = BOTTOM + 112  # where the bottom panels start

    # Left page: a side column, then Monday to Wednesday.
    (sx0, sx1), (dx0, dx1) = split(lx0, lx1, 0.31, 0.69, gap=6)
    mini_month(p, sx0, TOP - 4, sx1 - sx0, 100, "Month")
    top = panel(p, sx0, TOP - 110, sx1 - sx0, 132, "Priorities")
    checks(p, sx0 + 5, sx1 - 5, top, TOP - 242, 15)
    top = panel(p, sx0, TOP - 248, sx1 - sx0, TOP - 248 - low - 6, "Frequently used")
    ruled(p, sx0 + 5, sx1 - 5, top, low + 6, 15)
    day_columns(p, dx0, dx1, TOP - 4, low, [d[:3] for d in DAYS[:3]], gap=15)

    # Below: a personal to-do list and the habits and chores grid.
    (tx0, tx1), (hx0, hx1) = split(lx0, lx1, 0.46, 0.54, gap=6)
    top = panel(p, tx0, low - 6, tx1 - tx0, low - 6 - BOTTOM, "Personal to-do list")
    checks(p, tx0 + 5, tx1 - 5, top, BOTTOM + 2, 14)
    habit_grid(p, hx0, low - 6, hx1 - hx0, low - 6 - BOTTOM, "Habits & chores", 5)

    # Right page: Thursday to Sunday, then notes.
    day_columns(p, rx0, rx1, TOP - 4, low, [d[:3] for d in DAYS[3:]], gap=15)
    top = panel(p, rx0, low - 6, rx1 - rx0, low - 6 - BOTTOM, "Notes")
    ruled(p, rx0 + 5, rx1 - 5, top, BOTTOM + 2, 14)


def week_rows(sp, n=1):
    """A horizontal week: a row per day, notes and a to-do list."""
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Week of")
    rows = [(sp.left, DAYS[:4]), (sp.right, DAYS[4:])]
    for (x0, x1), days in rows:
        n_rows = 4
        rh = (TOP - 4 - BOTTOM) / n_rows
        for i in range(n_rows):
            y_top = TOP - 4 - i * rh
            if i < len(days):
                top = panel(p, x0, y_top, x1 - x0, rh - 6, days[i])
                (ax0, ax1), (bx0, bx1) = split(x0 + 5, x1 - 5, 0.62, 0.38, gap=8)
                ruled(p, ax0, ax1, top, y_top - rh + 8, 14)
                checks(p, bx0, bx1, top, y_top - rh + 8, 14)
            else:
                (ax0, ax1), (bx0, bx1) = split(x0, x1, 0.5, 0.5, gap=6)
                top = panel(p, ax0, y_top, ax1 - ax0, rh - 6, "Notes")
                ruled(p, ax0 + 5, ax1 - 5, top, y_top - rh + 8, 14)
                top = panel(p, bx0, y_top, bx1 - bx0, rh - 6, "Next week")
                checks(p, bx0 + 5, bx1 - 5, top, y_top - rh + 8, 14)


def _month_cells(p, x0, x1, top, bottom, labels):
    cw = (x1 - x0) / len(labels)
    for i, label in enumerate(labels):
        p.rect(x0 + i * cw, top - 15, cw, 15, fill=S().tab)
        caps(p, x0 + i * cw + 4, top - 11, label, 6.5)
    rh = (top - 15 - bottom) / 6
    for r in range(6):
        for i in range(len(labels)):
            x, y = x0 + i * cw, top - 15 - (r + 1) * rh
            p.rect(x, y, cw, rh, stroke=S().rule, width=0.6)
            p.rect(x + 3, y + rh - 13, 12, 10, stroke=tint_rule(), width=0.5)


def tint_rule():
    return tuple(c * 0.92 for c in S().rule)


def month(sp, n=1):
    """A month to fill in: Monday to Wednesday on the left beside goals and
    dates, Thursday to Sunday on the right above notes."""
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Month")
    _fill_in(p, sp.left[0] + 260, TOP + 10, "Year")
    lx0, lx1 = sp.left
    (sx0, sx1), (gx0, gx1) = split(lx0, lx1, 0.3, 0.7, gap=6)
    h = (TOP - 4 - BOTTOM) / 3
    for i, name in enumerate(("Goals", "Important dates", "Birthdays")):
        top = panel(p, sx0, TOP - 4 - i * h, sx1 - sx0, h - 6, name)
        (checks if name == "Goals" else ruled)(p, sx0 + 5, sx1 - 5, top, TOP - (i + 1) * h + 4, 15)
    _month_cells(p, gx0, gx1, TOP - 4, BOTTOM, ["Mon", "Tue", "Wed"])
    rx0, rx1 = sp.right
    _month_cells(p, rx0, rx1, TOP - 4, BOTTOM + 112, ["Thu", "Fri", "Sat", "Sun"])
    (ax0, ax1), (bx0, bx1) = split(rx0, rx1, 0.55, 0.45, gap=6)
    top = panel(p, ax0, BOTTOM + 106, ax1 - ax0, 106, "Notes")
    ruled(p, ax0 + 5, ax1 - 5, top, BOTTOM + 2, 14)
    top = panel(p, bx0, BOTTOM + 106, bx1 - bx0, 106, "To do this month")
    checks(p, bx0 + 5, bx1 - 5, top, BOTTOM + 2, 14)


def year(sp):
    """Twelve months to fill in, six to a page."""
    p = sp.page
    _fill_in(p, sp.left[0] + 180, TOP + 10, "Year")
    k = 0
    for x0, x1 in (sp.left, sp.right):
        cols = split(x0, x1, 1, 1, gap=8)
        rh = (TOP - 4 - BOTTOM) / 3
        for r in range(3):
            for c0, c1 in cols:
                k += 1
                mini_month(p, c0, TOP - 4 - r * rh, c1 - c0, rh - 8, f"{k}.  ________")


def goals(sp):
    """Yearly goals by area of life."""
    p = sp.page
    areas = [("Health & body", "Career & work"), ("Money", "Relationships"),
             ("Personal growth", "Fun & travel"), ("Home", "Learning")]
    halves = [areas[:2], areas[2:]]
    for (x0, x1), rows in zip((sp.left, sp.right), halves):
        rh = (TOP - 4 - BOTTOM) / 2
        for r, pair in enumerate(rows):
            for (c0, c1), name in zip(split(x0, x1, 1, 1, gap=8), pair):
                top = panel(p, c0, TOP - 4 - r * rh, c1 - c0, rh - 8, name)
                caps(p, c0 + 6, top - 12, "This year I will", 6, rgb=S().soft)
                ruled(p, c0 + 6, c1 - 6, top - 14, top - 52, 14)
                caps(p, c0 + 6, top - 66, "Steps", 6, rgb=S().soft)
                checks(p, c0 + 6, c1 - 6, top - 68, TOP - (r + 1) * rh + 6, 14)


def vision(sp):
    """A vision board: frames for photos and stickers, and words for the
    year."""
    p = sp.page
    x0, x1 = sp.left
    cols = split(x0, x1, 1, 1, gap=10)
    rh = (TOP - 4 - BOTTOM) / 3
    for r in range(3):
        for c0, c1 in cols:
            y = TOP - 4 - (r + 1) * rh + 6
            p.rect(c0, y, c1 - c0, rh - 10, stroke=S().rule, width=0.8)
            p.rect(c0 + 6, y + 6, c1 - c0 - 12, rh - 22, fill=S().tab)
    rx0, rx1 = sp.right
    top = panel(p, rx0, TOP - 4, rx1 - rx0, 90, "My word for the year")
    p.line(rx0 + 30, top - 50, rx1 - 30, top - 50, rgb=S().rule, width=1)
    top = panel(p, rx0, TOP - 104, rx1 - rx0, 170, "Affirmations")
    ruled(p, rx0 + 6, rx1 - 6, top, TOP - 274, 18)
    top = panel(p, rx0, TOP - 284, rx1 - rx0, TOP - 284 - BOTTOM, "This year I want to feel")
    ruled(p, rx0 + 6, rx1 - 6, top, BOTTOM + 2, 18)


def day(sp, n=1):
    """A full day: schedule and top three on the left; to-do, water, meals,
    gratitude and notes on the right."""
    p = sp.page
    _fill_in(p, sp.left[0] + 140, TOP + 10, "Date")
    lx0, lx1 = sp.left
    (ax0, ax1), (bx0, bx1) = split(lx0, lx1, 0.55, 0.45, gap=8)
    top = panel(p, ax0, TOP - 4, ax1 - ax0, TOP - 4 - BOTTOM, "Schedule")
    hours = list(range(6, 23))
    rh = (top - BOTTOM - 4) / len(hours)
    for i, h in enumerate(hours):
        y = top - (i + 1) * rh
        label = f"{h % 12 or 12}{'am' if h < 12 else 'pm'}"
        p.text(ax0 + 5, y + rh / 2 - 2, label, 6.5, rgb=S().soft, bold=True)
        p.line(ax0 + 30, y, ax1 - 5, y, rgb=S().rule, width=0.5)
        p.line(ax0 + 30, y + rh / 2, ax1 - 5, y + rh / 2, rgb=tint_rule(), width=0.3)
    top = panel(p, bx0, TOP - 4, bx1 - bx0, 100, "Top 3")
    for i in range(3):
        y = top - 20 - i * 26
        circle(p, bx0 + 12, y + 3, 5, S().accent, fill=False, width=0.8)
        p.line(bx0 + 22, y, bx1 - 6, y, rgb=S().rule, width=0.5)
    top = panel(p, bx0, TOP - 110, bx1 - bx0, 110, "Mood & energy")
    for i in range(5):
        circle(p, bx0 + 18 + i * ((bx1 - bx0 - 30) / 4), top - 24, 8, S().rule, fill=False, width=0.8)
    caps(p, bx0 + 6, top - 50, "Energy", 6, rgb=S().soft)
    bar(p, bx0 + 6, top - 66, bx1 - bx0 - 12, 10, 10)
    top = panel(p, bx0, TOP - 226, bx1 - bx0, TOP - 226 - BOTTOM, "Gratitude")
    ruled(p, bx0 + 5, bx1 - 5, top, BOTTOM + 2, 15)

    rx0, rx1 = sp.right
    (cx0, cx1), (ex0, ex1) = split(rx0, rx1, 0.55, 0.45, gap=8)
    top = panel(p, cx0, TOP - 4, cx1 - cx0, 300, "To do")
    checks(p, cx0 + 5, cx1 - 5, top, TOP - 304, 15)
    top = panel(p, cx0, TOP - 310, cx1 - cx0, TOP - 310 - BOTTOM, "Notes")
    ruled(p, cx0 + 5, cx1 - 5, top, BOTTOM + 2, 15)
    top = panel(p, ex0, TOP - 4, ex1 - ex0, 64, "Water")
    gw = (ex1 - ex0 - 12) / 8
    for i in range(8):
        p.rect(ex0 + 6 + i * gw + 2, top - 34, gw - 4, 26, stroke=S().rule, width=0.6)
    top = panel(p, ex0, TOP - 74, ex1 - ex0, 236, "Meals")
    for i, meal in enumerate(("Breakfast", "Lunch", "Dinner", "Snacks")):
        y = top - 14 - i * 54
        caps(p, ex0 + 6, y, meal, 6, rgb=S().soft)
        ruled(p, ex0 + 6, ex1 - 6, y - 2, y - 46, 14)
    top = panel(p, ex0, TOP - 316, ex1 - ex0, TOP - 316 - BOTTOM, "Tomorrow")
    checks(p, ex0 + 5, ex1 - 5, top, BOTTOM + 2, 15)


def day_simple(sp, n=1):
    """A simple day: priorities and to-do on the left, notes on the right."""
    p = sp.page
    _fill_in(p, sp.left[0] + 140, TOP + 10, "Date")
    x0, x1 = sp.left
    top = panel(p, x0, TOP - 4, x1 - x0, 110, "Most important")
    checks(p, x0 + 5, x1 - 5, top, TOP - 114, 22)
    top = panel(p, x0, TOP - 120, x1 - x0, TOP - 120 - BOTTOM, "To do")
    checks(p, x0 + 5, x1 - 5, top, BOTTOM + 2, 17)
    rx0, rx1 = sp.right
    top = panel(p, rx0, TOP - 4, rx1 - rx0, TOP - 4 - BOTTOM, "Notes")
    ruled(p, rx0 + 5, rx1 - 5, top, BOTTOM + 2, 17)


TITLES = {
    week: "Weekly planner",
    week_rows: "Week at a glance",
    month: "Monthly planner",
    year: "Year at a glance",
    goals: "Yearly goals",
    vision: "Vision board",
    day: "Daily planner",
    day_simple: "Simple day",
}

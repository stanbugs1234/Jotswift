"""Habit spreads: the circular habit tracker, a monthly habit grid, the
year in moods, and sleep and water."""

from spreads.kit import *  # noqa: F401,F403
from spreads.plan import _fill_in


def _arc_line(p, cx, cy, r0, r1, angle):
    p.line(cx + r0 * math.cos(angle), cy + r0 * math.sin(angle),
           cx + r1 * math.cos(angle), cy + r1 * math.sin(angle), rgb=S().rule, width=0.5)


def circle_tracker(sp, n=1):
    """A dial of 31 days with a ring per habit (fill a segment each day),
    and a key and notes beside it."""
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Month")
    x0, x1 = sp.left
    cx, cy = (x0 + x1) / 2, (TOP + BOTTOM) / 2 - 6
    r_out = min((x1 - x0) / 2, (TOP - BOTTOM) / 2) - 16
    r_in = r_out * 0.24
    rings = 8
    step = (r_out - r_in) / rings
    for k in range(rings + 1):
        circle(p, cx, cy, r_in + k * step, S().rule if k else S().soft, fill=False, width=0.7 if k else 1)
    for d in range(31):
        a = math.pi / 2 - d * 2 * math.pi / 31
        _arc_line(p, cx, cy, r_in, r_out, a)
        mid = a - math.pi / 31
        p.text(cx + (r_out + 8) * math.cos(mid), cy + (r_out + 8) * math.sin(mid) - 2.5, str(d + 1), 6.5,
               rgb=S().accent, bold=True, center=True)
    # Ring numbers along the top, to match the key.
    for k in range(rings):
        p.text(cx + 2, cy + r_in + (k + 0.5) * step - 2.5, str(k + 1), 5.5, rgb=S().soft, bold=True, center=True)
    p.text(cx, cy - 3, "HABITS", 6.5, rgb=S().accent, bold=True, center=True)

    rx0, rx1 = sp.right
    top = panel(p, rx0, TOP - 4, rx1 - rx0, 250, "Habits (ring 1 is the inside)")
    colours = sp.colourway.tabs
    for k in range(rings):
        y = top - 22 - k * 27
        p.text(rx0 + 10, y, str(k + 1), 9, rgb=S().accent, bold=True)
        p.rect(rx0 + 24, y - 3, 14, 12, fill=colours[k % len(colours)])
        p.line(rx0 + 46, y - 3, rx1 - 10, y - 3, rgb=S().rule, width=0.5)
    (ax0, ax1), (bx0, bx1) = split(rx0, rx1, 1, 1, gap=8)
    top = panel(p, ax0, TOP - 260, ax1 - ax0, TOP - 260 - BOTTOM, "Wins")
    ruled(p, ax0 + 5, ax1 - 5, top, BOTTOM + 2, 15)
    top = panel(p, bx0, TOP - 260, bx1 - bx0, TOP - 260 - BOTTOM, "Next month")
    checks(p, bx0 + 5, bx1 - 5, top, BOTTOM + 2, 15)


def _days(p, x0, x1, top, bottom, rows, name_share=0.28, days=31):
    name_w = (x1 - x0) * name_share
    cw = (x1 - x0 - name_w) / days
    for d in range(days):
        p.text(x0 + name_w + d * cw + cw / 2, top - 9, str(d + 1), 5, rgb=S().soft, bold=True, center=True)
    rh = (top - 14 - bottom) / rows
    for r in range(rows):
        y = top - 14 - (r + 1) * rh
        p.line(x0 + 4, y + 2, x0 + name_w - 4, y + 2, rgb=S().rule, width=0.5)
        s = min(cw, rh) - 2
        for d in range(days):
            p.rect(x0 + name_w + d * cw + (cw - s) / 2, y + (rh - s) / 2, s, s, stroke=S().rule, width=0.4)


def habit_month(sp, n=1):
    """Twelve habits by thirty-one days, and a streak and notes page."""
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Month")
    x0, x1 = sp.left
    top = panel(p, x0, TOP - 4, x1 - x0, TOP - 4 - BOTTOM, "Habit tracker")
    _days(p, x0 + 4, x1 - 4, top, BOTTOM + 4, 16)
    rx0, rx1 = sp.right
    ledger_cols = [("Habit", 0), ("Goal", 0.45), ("Best streak", 0.66), ("Done", 0.86)]
    top = panel(p, rx0, TOP - 4, rx1 - rx0, 260, "How it went")
    table(p, top - 2, ledger_cols, 12, row_h=17, x0=rx0 + 4, x1=rx1 - 4)
    top = panel(p, rx0, TOP - 270, rx1 - rx0, TOP - 270 - BOTTOM, "Reflection")
    ruled(p, rx0 + 5, rx1 - 5, top, BOTTOM + 2, 15)


def mood_year(sp):
    """A year of moods: a square per day to colour, with a key."""
    p = sp.page
    _fill_in(p, sp.left[0] + 180, TOP + 10, "Year")
    x0, x1 = sp.left
    top = panel(p, x0, TOP - 4, x1 - x0, TOP - 4 - BOTTOM, "Year in pixels")
    cw = (x1 - x0 - 30) / 12
    for m in range(12):
        p.text(x0 + 24 + m * cw + cw / 2, top - 10, "JFMAMJJASOND"[m], 6.5, rgb=S().soft, bold=True, center=True)
    rh = (top - 16 - BOTTOM - 6) / 31
    for d in range(31):
        y = top - 16 - (d + 1) * rh
        p.text(x0 + 8, y + rh / 2 - 2, str(d + 1), 5.5, rgb=S().soft, bold=True)
        for m in range(12):
            p.rect(x0 + 24 + m * cw + 1, y + 0.6, cw - 2, rh - 1.2, stroke=S().rule, width=0.4)
    rx0, rx1 = sp.right
    top = panel(p, rx0, TOP - 4, rx1 - rx0, 220, "Key")
    for i, mood in enumerate(("Amazing", "Happy", "Calm", "Okay", "Tired", "Stressed", "Sad")):
        y = top - 22 - i * 26
        p.rect(rx0 + 10, y - 4, 16, 14, stroke=S().soft, width=0.7)
        p.text(rx0 + 34, y, mood, 9, rgb=S().ink)
        p.line(rx0 + 110, y - 3, rx1 - 10, y - 3, rgb=S().rule, width=0.5)
    top = panel(p, rx0, TOP - 230, rx1 - rx0, TOP - 230 - BOTTOM, "What I notice")
    ruled(p, rx0 + 5, rx1 - 5, top, BOTTOM + 2, 15)


def sleep_water(sp, n=1):
    """A month of sleep (bed, wake, hours) and water (eight glasses)."""
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Month")
    x0, x1 = sp.left
    top = panel(p, x0, TOP - 4, x1 - x0, TOP - 4 - BOTTOM, "Sleep")
    table(p, top - 2, [("Day", 0), ("Bed", 0.12), ("Woke", 0.28), ("Hours (0-12)", 0.44)], 31,
          row_h=(top - 26 - BOTTOM) / 31, x0=x0 + 4, x1=x1 - 4)
    # Twelve boxes per night in the hours column, to shade hours slept.
    hx0 = x0 + 4 + (x1 - x0 - 8) * 0.44
    cw = (x1 - 4 - hx0) / 12
    row_h = (top - 26 - BOTTOM) / 31
    for d in range(31):
        y = top - 2 - 22 - (d + 1) * row_h
        for h in range(12):
            p.rect(hx0 + h * cw + 1.5, y + 1.5, cw - 3, row_h - 3, stroke=S().rule, width=0.35)
    rx0, rx1 = sp.right
    top2 = panel(p, rx0, TOP - 4, rx1 - rx0, TOP - 4 - BOTTOM, "Water (a glass a box)")
    _days_rows = 31
    rh = (top2 - 14 - BOTTOM - 4) / _days_rows
    gw = (rx1 - rx0 - 40) / 8
    for d in range(_days_rows):
        y = top2 - 14 - (d + 1) * rh
        p.text(rx0 + 8, y + rh / 2 - 2, str(d + 1), 5.5, rgb=S().soft, bold=True)
        for g in range(8):
            p.rect(rx0 + 30 + g * gw + 2, y + 1, gw - 4, rh - 2, stroke=S().rule, width=0.4)
    _ = cw


TITLES = {
    circle_tracker: "Circle habit tracker",
    habit_month: "Habit tracker",
    mood_year: "Year in moods",
    sleep_water: "Sleep & water",
}

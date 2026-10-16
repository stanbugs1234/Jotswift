"""Preconstruction project spreads: one notebook per project being
estimated, from the dashboard through scope, dates, meetings, site visits,
RFIs, takeoff, quotes, risks, review, bid day and post bid."""

from spreads.kit import *  # noqa: F401,F403
from make_planner import tint
from planner_nav import chevron

FIELD = 6.5  # size of field labels

DIVISIONS = [
    ("01", "General requirements"), ("02", "Existing conditions"), ("03", "Concrete"),
    ("04", "Masonry"), ("05", "Metals"), ("06", "Wood, plastics & composites"),
    ("07", "Thermal & moisture protection"), ("08", "Openings"), ("09", "Finishes"),
    ("10", "Specialties"), ("11", "Equipment"), ("12", "Furnishings"),
    ("13", "Special construction"), ("14", "Conveying equipment"), ("21", "Fire suppression"),
    ("22", "Plumbing"), ("23", "HVAC"), ("25", "Integrated automation"), ("26", "Electrical"),
    ("27", "Communications"), ("28", "Electronic safety & security"), ("31", "Earthwork"),
    ("32", "Exterior improvements"), ("33", "Utilities"),
]


def _fields(p, x0, x1, top, names, gap=21):
    """"LABEL ________" rows from [top] down; returns the y below them."""
    for i, name in enumerate(names):
        y = top - (i + 1) * gap
        caps(p, x0, y + 3, name, FIELD, rgb=S().soft)
        p.line(x0 + mp.text_width(name.upper(), FIELD) + 6, y + 2, x1, y + 2, rgb=S().rule, width=0.6)
    return top - len(names) * gap


def _field_panel(p, x0, x1, top, title, names, gap=21, cols=1):
    rows = (len(names) + cols - 1) // cols
    h = 15 + rows * gap + 8
    t = panel(p, x0, top, x1 - x0, h, title)
    for c, (c0, c1) in enumerate(split(x0 + 6, x1 - 6, *([1] * cols), gap=12)):
        _fields(p, c0, c1, t, names[c * rows:(c + 1) * rows], gap)
    return top - h


def _grid(p, x0, x1, top, cols, rows, row_h=15, labels=(), boxes=(), title=None, bold_rows=()):
    """A table with small caps headings. [cols] is (heading, start fraction);
    [labels] fills the first column; [boxes] are columns with a tick box
    in each row. Returns the y of its bottom edge."""
    if title:
        top = panel(p, x0, top, x1 - x0, 15, title) - 0
        top = top  # the strip sits on the table
    w = x1 - x0
    head = 15
    bottom = top - head - rows * row_h
    p.rect(x0, top - head, w, head, fill=tint(S().tab, 0.0))
    p.rect(x0, bottom, w, top - bottom, stroke=S().rule, width=0.6)
    starts = [at for _, at in cols] + [1]
    for name, at in cols:
        caps(p, x0 + w * at + 4, top - head + 5, name, 6, rgb=S().ink)
    for at in starts[1:-1]:
        p.line(x0 + w * at, top, x0 + w * at, bottom, rgb=S().rule, width=0.5)
    for r in range(rows):
        y = top - head - (r + 1) * row_h
        if r + 1 < rows:
            p.line(x0, y, x1, y, rgb=S().rule, width=0.4)
        if r < len(labels) and labels[r]:
            p.text(x0 + w * starts[0] + 4, y + row_h / 2 - 2.5, labels[r], 7.5, rgb=S().ink,
                   bold=r in bold_rows)
        for c in boxes:
            cx = x0 + w * (starts[c] + starts[c + 1]) / 2
            s = min(7, row_h - 6)
            p.rect(cx - s / 2, y + (row_h - s) / 2, s, s, stroke=S().soft, width=0.6)
    return bottom


def _rows_to(top, bottom, row_h, head=15):
    return max(1, int((top - head - bottom) / row_h))


def _ruled_panel(p, x0, x1, top, bottom, title, gap=15):
    t = panel(p, x0, top, x1 - x0, top - bottom, title)
    ruled(p, x0 + 5, x1 - 5, t, bottom + 2, gap)


def _checks_panel(p, x0, x1, top, bottom, title, items=(), gap=16):
    """A panel of tick boxes, the first ones already named."""
    t = panel(p, x0, top, x1 - x0, top - bottom, title)
    y = t - gap
    i = 0
    while y >= bottom + 2:
        p.rect(x0 + 6, y + 2, 7, 7, stroke=S().soft, width=0.7)
        if i < len(items):
            p.text(x0 + 19, y + 3, items[i], 7.5, rgb=S().ink)
        else:
            p.line(x0 + 17, y + 1, x1 - 6, y + 1, rgb=S().rule, width=0.5)
        y -= gap
        i += 1


# 00 Dashboard


def dashboard(sp, entries, tabs):
    """Project details and status on the left; a tile for every section on
    the right (each a link), with the key numbers."""
    p = sp.page
    x0, x1 = sp.left
    y = _field_panel(p, x0, x1, TOP - 4, "Project", [
        "Project", "Project #", "Owner / client", "Architect / engineer", "Location",
        "Delivery method", "Bid type", "Size (SF)", "Budget", "Bid due (date / time)",
        "Bid to", "Estimator",
    ], gap=20)
    _checks_panel(p, x0, x1, y - 8, BOTTOM, "Status", [
        "Scope reviewed", "Key dates set", "Strategy meeting held", "Site visited",
        "RFIs sent / answered", "Takeoff complete", "Quotes leveled", "Risks reviewed",
        "Bid reviewed", "Bid submitted", "Results recorded",
    ], gap=17)

    rx0, rx1 = sp.right
    sections = tabs[1:]
    rows = (len(sections) + 1) // 2
    tile_h = 36
    t = panel(p, rx0, TOP - 4, rx1 - rx0, 15 + rows * (tile_h + 6) + 6, "Project sections: tap to open")
    colours = sp.colourway.tabs
    for i, (tab, target) in enumerate(sections):
        c, r = i % 2, i // 2
        c0, c1 = split(rx0 + 6, rx1 - 6, 1, 1, gap=8)[c]
        ty = t - 6 - (r + 1) * (tile_h + 6) + 6
        colour = colours[(i + 1) % len(colours)]
        title = next(e[0] for e in entries if e[1] == tab)
        number, _, name = title.partition(" - ")
        p.rect(c0, ty, c1 - c0, tile_h, stroke=S().rule, width=0.7)
        p.rect(c0, ty, 26, tile_h, fill=colour)
        p.text(c0 + 13, ty + tile_h / 2 - 4, number, 10, rgb=(1, 1, 1), bold=True, center=True)
        p.text(c0 + 33, ty + tile_h / 2 + 1, name or title, 9, rgb=S().ink, bold=True)
        count = sum(1 for e in entries if e[1] == tab and e[2] != "contents")
        if count > 1:
            p.text(c0 + 33, ty + 7, f"{count} pages", 6.5, rgb=S().soft)
        chevron(p, c1 - 10, ty + tile_h / 2, 7, S().soft)
        p.link(c0, ty, c1 - c0, tile_h, target)
    y = t - 6 - rows * (tile_h + 6) - 8
    y = _field_panel(p, rx0, rx1, y, "Key numbers", [
        "Base bid", "Alternates", "Fee %", "Low bid", "Our rank", "Result",
    ], gap=19, cols=2)
    _ruled_panel(p, rx0, rx1, y - 8, BOTTOM, "Notes")


# 01 Scope


def scope(sp, n=1):
    p = sp.page
    x0, x1 = sp.left
    rx0, rx1 = sp.right
    if n == 1:
        _ruled_panel(p, x0, x1, TOP - 4, TOP - 170, "Project description")
        (a0, a1), (b0, b1) = split(x0, x1, 1, 1)
        _checks_panel(p, a0, a1, TOP - 178, BOTTOM, "Inclusions")
        _checks_panel(p, b0, b1, TOP - 178, BOTTOM, "Exclusions")
        _grid(p, rx0, rx1, TOP - 4, [("Div", 0), ("Scope", 0.09), ("Self", 0.6), ("Sub", 0.7),
                                     ("By others", 0.8), ("N/A", 0.92)],
              len(DIVISIONS), row_h=(TOP - 4 - 15 - BOTTOM) / len(DIVISIONS),
              labels=[d for d, _ in DIVISIONS], boxes=(2, 3, 4, 5))
        w = rx1 - rx0
        rh = (TOP - 4 - 15 - BOTTOM) / len(DIVISIONS)
        for r, (_, name) in enumerate(DIVISIONS):
            y = TOP - 4 - 15 - (r + 1) * rh
            p.text(rx0 + w * 0.09 + 4, y + rh / 2 - 2.5, name, 7.5, rgb=S().ink)
    else:
        _ruled_panel(p, x0, x1, TOP - 4, (TOP + BOTTOM) / 2 + 4, "Clarifications & assumptions")
        _grid(p, x0, x1, (TOP + BOTTOM) / 2 - 4, [("Alt", 0), ("Alternate", 0.1), ("Add / deduct", 0.75)],
              _rows_to((TOP + BOTTOM) / 2 - 4, BOTTOM, 18), row_h=18,
              labels=[str(i) for i in range(1, 30)])
        _grid(p, rx0, rx1, TOP - 4, [("Allowance", 0), ("Amount", 0.7)], 8, row_h=18)
        _ruled_panel(p, rx0, rx1, TOP - 4 - 15 - 8 * 18 - 10, BOTTOM, "Scope gaps & questions (for RFIs)")


# 02 Key dates

MILESTONES = [
    "Pre-bid meeting", "Site visit", "RFI deadline", "Last addendum", "Sub bids due",
    "Bid due", "Interview", "Award", "Notice to proceed", "Substantial completion",
]


def dates(sp):
    p = sp.page
    x0, x1 = sp.left
    rows = _rows_to(TOP - 4, BOTTOM, 24)
    _grid(p, x0, x1, TOP - 4, [("Milestone", 0), ("Date", 0.4), ("Time", 0.56), ("Notes", 0.68),
                               ("Done", 0.9)], rows, row_h=24, labels=MILESTONES, boxes=(4,))
    rx0, rx1 = sp.right
    (a0, a1), (b0, b1) = split(rx0, rx1, 1, 1)
    mini_month(p, a0, TOP - 4, a1 - a0, 170, "Month")
    mini_month(p, b0, TOP - 4, b1 - b0, 170, "Month")
    _ruled_panel(p, rx0, rx1, TOP - 184, BOTTOM, "Schedule notes")


# 03 Strategy meeting


def strategy(sp, n=1):
    p = sp.page
    x0, x1 = sp.left
    y = _field_panel(p, x0, x1, TOP - 4, "Meeting", ["Date", "Time", "Location", "Attendees"],
                     gap=20, cols=2)
    _checks_panel(p, x0, x1, y - 8, y - 150, "Agenda")
    y -= 158
    rows = ["Client / relationship", "Competition", "Project risk", "Our capacity",
            "Margin potential", "Schedule fit", "Fits our strengths"]
    bottom = _grid(p, x0, x1, y, [("Go / no-go factor", 0), ("Low", 0.42), ("Med", 0.52), ("High", 0.62),
                                  ("Notes", 0.72)], len(rows), row_h=17, labels=rows, boxes=(1, 2, 3))
    t = bottom - 8
    caps(p, x0, t - 12, "Decision", 8)
    for i, label in enumerate(["Go", "No go", "Revisit"]):
        bx = x0 + 70 + i * 70
        p.rect(bx, t - 14, 9, 9, stroke=S().soft, width=0.8)
        p.text(bx + 14, t - 12, label, 8, rgb=S().ink, bold=True)
    _ruled_panel(p, x0, x1, t - 24, BOTTOM, "Discussion")

    rx0, rx1 = sp.right
    _ruled_panel(p, rx0, rx1, TOP - 4, TOP - 140, "Approach: self-perform, key trades, schedule")
    _ruled_panel(p, rx0, rx1, TOP - 148, TOP - 260, "Decisions")
    _grid(p, rx0, rx1, TOP - 268, [("Action item", 0), ("Owner", 0.6), ("Due", 0.78), ("Done", 0.9)],
          _rows_to(TOP - 268, BOTTOM, 18), row_h=18, boxes=(3,))


# 04 Site visit


def site(sp, n=1):
    p = sp.page
    x0, x1 = sp.left
    y = _field_panel(p, x0, x1, TOP - 4, "Visit", ["Date", "Time", "Weather", "Site contact", "Attendees"],
                     gap=20, cols=2)
    rows = ["Access & haul routes", "Laydown / staging", "Utilities", "Existing conditions", "Demolition",
            "Hazmat", "Parking", "Security / fencing", "Neighbours / noise", "Soils / grading",
            "Occupied areas", ""]
    bottom = _grid(p, x0, x1, y - 8, [("Condition", 0), ("OK", 0.4), ("Concern", 0.5), ("Notes", 0.64)],
                   len(rows), row_h=19, labels=rows, boxes=(1, 2))
    _ruled_panel(p, x0, x1, bottom - 8, BOTTOM, "Observations")

    rx0, rx1 = sp.right
    t = panel(p, rx0, TOP - 4, rx1 - rx0, 280, "Photos: add them from the toolbar")
    (a0, a1), (b0, b1) = split(rx0 + 6, rx1 - 6, 1, 1)
    fh = (t - (TOP - 284) - 18) / 2
    for r in range(2):
        for c0, c1 in ((a0, a1), (b0, b1)):
            fy = t - 6 - (r + 1) * fh - r * 6
            p.rect(c0, fy, c1 - c0, fh, stroke=tint(S().rule, 0.2), width=0.6)
            p.text((c0 + c1) / 2, fy + fh / 2 - 3, "Photo", 7, rgb=S().soft, center=True)
    _checks_panel(p, rx0, rx1, TOP - 292, BOTTOM, "Questions to raise as RFIs")


# 05 RFIs

RFI_ROW = 22


def rfis(sp, n=1):
    """A log across both pages: the question on the left, its answer on the
    right, on the same rows."""
    p = sp.page
    rows = _rows_to(TOP - 4, BOTTOM, RFI_ROW)
    numbers = [str((n - 1) * rows + i) for i in range(1, rows + 1)]
    x0, x1 = sp.left
    _grid(p, x0, x1, TOP - 4, [("#", 0), ("Sent", 0.07), ("Dwg / spec", 0.2), ("Question", 0.38)],
          rows, row_h=RFI_ROW, labels=numbers)
    rx0, rx1 = sp.right
    _grid(p, rx0, rx1, TOP - 4, [("#", 0), ("Sent to", 0.07), ("Due", 0.27), ("Answer / addendum", 0.4),
                                 ("Closed", 0.88)], rows, row_h=RFI_ROW, labels=numbers, boxes=(4,))


# 06 Takeoff


def takeoff(sp, n=1):
    p = sp.page
    cols = [("Item / description", 0), ("CSI", 0.42), ("Qty", 0.52), ("Unit", 0.64), ("Unit $", 0.74),
            ("Total", 0.86)]
    x0, x1 = sp.left
    y = _field_panel(p, x0, x1, TOP - 4, "Takeoff", ["Division / trade", "Sheets", "By", "Date"],
                     gap=19, cols=2)
    _grid(p, x0, x1, y - 8, cols, _rows_to(y - 8, BOTTOM, 17), row_h=17)
    rx0, rx1 = sp.right
    bottom = _grid(p, rx0, rx1, TOP - 4, cols, _rows_to(TOP - 4, BOTTOM + 40, 17), row_h=17)
    p.rect(rx0, BOTTOM, rx1 - rx0, bottom - BOTTOM - 8, fill=S().tab)
    caps(p, rx0 + 8, BOTTOM + (bottom - BOTTOM - 8) / 2 - 3, "Subtotal", 8, rgb=S().ink)
    p.line(rx0 + (rx1 - rx0) * 0.86, BOTTOM + 6, rx1 - 6, BOTTOM + 6, rgb=S().soft, width=0.8)


# 07 Quotes


def quotes(sp, n=1):
    """Bid leveling for one trade: up to four bidders side by side."""
    p = sp.page
    x0, x1 = sp.left
    y = _field_panel(p, x0, x1, TOP - 4, "Trade", ["Trade", "CSI division"], gap=19, cols=2)
    rows = (["Bidder", "Contact", "Base bid"] + ["Scope item"] + [""] * 9
            + ["Exclusions", "Alternate 1", "Alternate 2", "Adjustments", "Adjusted total", "Selected"])
    row_h = (y - 8 - 15 - BOTTOM) / len(rows)
    _grid(p, x0, x1, y - 8, [("", 0), ("A", 0.28), ("B", 0.46), ("C", 0.64), ("D", 0.82)],
          len(rows), row_h=row_h, labels=rows, bold_rows=(0, 2, len(rows) - 2))
    w = x1 - x0
    sy = y - 8 - 15 - len(rows) * row_h
    for c in (0.28, 0.46, 0.64, 0.82):
        cx = x0 + w * (c + 0.09)
        p.rect(cx - 3.5, sy + (row_h - 7) / 2, 7, 7, stroke=S().soft, width=0.6)
    rx0, rx1 = sp.right
    bottom = _grid(p, rx0, rx1, TOP - 4, [("Sub", 0), ("Contact", 0.36), ("Phone / email", 0.6),
                                          ("Bidding?", 0.86)], 10, row_h=18, boxes=(3,))
    _ruled_panel(p, rx0, rx1, bottom - 8, BOTTOM, "Clarifications & follow-ups")


# 08 Risks


def risks(sp, n=1):
    p = sp.page
    x0, x1 = sp.left
    rx0, rx1 = sp.right
    if n == 1:
        rows = _rows_to(TOP - 4, BOTTOM, 26)
        numbers = [str(i) for i in range(1, rows + 1)]
        _grid(p, x0, x1, TOP - 4, [("#", 0), ("Risk", 0.07), ("Category", 0.6), ("L", 0.8), ("I", 0.9)],
              rows, row_h=26, labels=numbers)
        _grid(p, rx0, rx1, TOP - 4, [("#", 0), ("Mitigation", 0.07), ("Owner", 0.6), ("$ contingency", 0.78)],
              rows, row_h=26, labels=numbers)
        caps(p, x0, BOTTOM - 10, "Likelihood and impact: L / M / H", 6, rgb=S().soft)
    else:
        _grid(p, x0, x1, TOP - 4, [("Opportunity / VE idea", 0), ("Savings $", 0.64), ("Accepted", 0.84)],
              _rows_to(TOP - 4, BOTTOM, 22), row_h=22, boxes=(2,))
        y = _field_panel(p, rx0, rx1, TOP - 4, "Contingency", ["Design", "Construction", "Escalation",
                                                               "Owner", "Total"], gap=20)
        _ruled_panel(p, rx0, rx1, y - 8, BOTTOM, "Risk notes")


# 09 Bid review

MARKUPS = ["Direct cost subtotal", "General conditions", "General requirements", "Overhead", "Fee",
           "Insurance", "Bond", "Contingency", "Escalation", "Total bid"]
BID_FORM = ["Bid form complete", "All addenda acknowledged", "Bid bond / security", "Alternates priced",
            "Unit prices filled in", "Allowances included", "Sub list (if required)", "Signed & dated",
            "Insurance requirements met", "Schedule / duration stated", "Exclusions & clarifications",
            "Copy saved"]


def review(sp, n=1):
    p = sp.page
    x0, x1 = sp.left
    rx0, rx1 = sp.right
    if n == 1:
        rows = len(DIVISIONS) + 1
        rh = (TOP - 4 - 15 - BOTTOM) / rows
        _grid(p, x0, x1, TOP - 4, [("Div", 0), ("Description", 0.09), ("Cost", 0.6), ("$/SF", 0.82)],
              rows, row_h=rh, labels=[d for d, _ in DIVISIONS] + ["Total"], bold_rows=(rows - 1,))
        w = x1 - x0
        for r, (_, name) in enumerate(DIVISIONS):
            y = TOP - 4 - 15 - (r + 1) * rh
            p.text(x0 + w * 0.09 + 4, y + rh / 2 - 2.5, name, 7.5, rgb=S().ink)
        bottom = _grid(p, rx0, rx1, TOP - 4, [("Markup", 0), ("%", 0.6), ("Amount", 0.72)], len(MARKUPS),
                       row_h=20, labels=MARKUPS, bold_rows=(len(MARKUPS) - 1,))
        _grid(p, rx0, rx1, bottom - 10, [("Alt", 0), ("Description", 0.1), ("Add / deduct", 0.72)],
              _rows_to(bottom - 10, BOTTOM, 20), row_h=20, labels=[str(i) for i in range(1, 20)])
    else:
        _checks_panel(p, x0, x1, TOP - 4, BOTTOM, "Bid form checklist", BID_FORM, gap=20)
        y = _field_panel(p, rx0, rx1, TOP - 4, "Sign-off", ["Reviewed by", "Date", "Approved by", "Date"],
                         gap=20, cols=2)
        _ruled_panel(p, rx0, rx1, y - 8, BOTTOM, "Review notes")


# 10 Bid day

TIMES = ["7:00", "8:00", "9:00", "10:00", "10:30", "11:00", "11:30", "12:00", "12:30", "1:00",
         "1:30", "2:00", "2:30", "3:00"]


def bid_day(sp):
    p = sp.page
    x0, x1 = sp.left
    bottom = _grid(p, x0, x1, TOP - 4, [("Time", 0), ("Task", 0.14), ("Done", 0.88)], len(TIMES),
                   row_h=19, labels=TIMES, boxes=(2,))
    _checks_panel(p, x0, x1, bottom - 8, BOTTOM, "Before it goes", [
        "Bid form signed", "Bond attached", "Addenda acknowledged", "Alternates filled in",
        "Uploaded / delivered", "Receipt confirmed",
    ])
    rx0, rx1 = sp.right
    bottom = _grid(p, rx0, rx1, TOP - 4, [("Trade", 0), ("Low $", 0.3), ("Sub", 0.5), ("Plug", 0.74),
                                          ("Final $", 0.84)], 14, row_h=18, boxes=(3,))
    _ruled_panel(p, rx0, rx1, bottom - 8, bottom - 110, "Last-minute adjustments")
    t = panel(p, rx0, bottom - 118, rx1 - rx0, bottom - 118 - BOTTOM, "Final bid")
    p.text(rx0 + 8, t - 26, "$", 18, rgb=S().accent, bold=True)
    p.line(rx0 + 24, t - 28, rx1 - 8, t - 28, rgb=S().soft, width=1)
    _fields(p, rx0 + 6, rx1 - 6, t - 32, ["Submitted at", "Submitted by"], gap=20)


# 11 Post bid


def post_bid(sp):
    p = sp.page
    x0, x1 = sp.left
    bottom = _grid(p, x0, x1, TOP - 4, [("Bidder", 0), ("Base", 0.4), ("Alts", 0.58), ("Total", 0.72),
                                        ("Rank", 0.88)], 12, row_h=20)
    y = _field_panel(p, x0, x1, bottom - 8, "Result", ["Our number", "Low number", "Difference %",
                                                       "Awarded to"], gap=20, cols=2)
    _ruled_panel(p, x0, x1, y - 8, BOTTOM, "Debrief")
    rx0, rx1 = sp.right
    _ruled_panel(p, rx0, rx1, TOP - 4, (TOP + BOTTOM) / 2 + 4, "Lessons learned")
    _checks_panel(p, rx0, rx1, (TOP + BOTTOM) / 2 - 4, BOTTOM, "Follow-ups")


TITLES = {
    dashboard: "Dashboard", scope: "Scope", dates: "Key dates", strategy: "Strategy meeting",
    site: "Site visit", rfis: "RFI log", takeoff: "Takeoff", quotes: "Quotes", risks: "Risks",
    review: "Bid review", bid_day: "Bid day", post_bid: "Post bid",
}

"""Work pages: projects, OKRs, one-to-ones, mind maps, calls, timesheets,
decisions and retrospectives."""

import math

from layouts.kit import *  # noqa: F401,F403


def project_planner():
    p = page("Project", False)
    field(p, LEFT, TOP - 24, "Name", LEFT + 320)
    field(p, LEFT + 336, TOP - 24, "Due", RIGHT)
    label(p, LEFT, TOP - 60, "Goal")
    lines(p, LEFT, RIGHT, TOP - 84, 2)
    label(p, LEFT, TOP - 138, "Milestones")
    bottom = table(p, TOP - 148, [("Milestone", 0), ("Owner", 0.55), ("Due", 0.75), ("Done", 0.9)], 6, row_h=26)
    label(p, LEFT, bottom - 26, "Tasks")
    xs, w = columns(p, LEFT, RIGHT, 2)
    for x in xs:
        checkbox_rows(p, x, x + w, bottom - 52, int((bottom - 52 - BOTTOM) / 26) + 1, gap=26)
    return p, "Project planner"


def okrs():
    p = page("Objectives & key results", "Quarter  ________________", size=26)
    bh = (TOP - 44 - BOTTOM - 2 * 14) / 3
    for i in range(3):
        y = TOP - 44 - (i + 1) * bh - i * 14
        box(p, LEFT, y, RIGHT - LEFT, bh, f"Objective {i + 1}")
        p.line(LEFT + 90, y + bh - 20, RIGHT - 12, y + bh - 20)
        for k in range(3):
            ky = y + bh - 52 - k * 44
            p.text(LEFT + 12, ky, f"KR {k + 1}", 9, rgb=s().soft, bold=True)
            p.line(LEFT + 44, ky - 3, RIGHT - 190, ky - 3)
            bar(p, RIGHT - 176, ky - 6, 164, 12, 10)
    return p, "OKRs"


def one_on_one():
    p = page("1:1", False)
    field(p, LEFT, TOP - 24, "With", LEFT + 300)
    field(p, LEFT + 316, TOP - 24, "Date", RIGHT)
    xs, w = columns(p, LEFT, RIGHT, 2)
    top = TOP - 52
    for x, name in zip(xs, ("Their topics", "My topics")):
        box(p, x, top - 200, w, 200, name)
        checkbox_rows(p, x + 10, x + w - 10, top - 44, 6, gap=26)
    label(p, LEFT, top - 230, "Notes")
    lines(p, LEFT, RIGHT, top - 254, 9)
    label(p, LEFT, 196, "Follow-ups")
    table(p, 186, [("Action", 0), ("Who", 0.62), ("When", 0.8)], 5, row_h=26)
    return p, "One-to-one"


def mind_map():
    p = page("Mind map")
    cx, cy = (LEFT + RIGHT) / 2, (TOP - 40 + BOTTOM) / 2
    for k in range(6):
        a = math.pi / 2 + k * math.pi / 3
        bx, by = cx + 160 * math.cos(a), cy + 230 * math.sin(a)
        p.line(cx + 64 * math.cos(a), cy + 64 * math.sin(a), bx - 30 * math.cos(a), by - 26 * math.sin(a),
               rgb=tint(s().accent, 0.4), width=1.4)
        p.rect(bx - 55, by - 20, 110, 40, stroke=s().rule, width=1)
        # Two twigs leaving the far side of each box.
        ex, ey = bx + 55 * math.copysign(1, math.cos(a)) if abs(math.cos(a)) > 0.1 else bx, \
            by + 20 * math.copysign(1, math.sin(a))
        for j in (-0.45, 0.45):
            a2 = a + j
            p.line(ex, ey, ex + 44 * math.cos(a2), ey + 44 * math.sin(a2), rgb=s().rule, width=0.8)
    circle(p, cx, cy, 64, tint(s().accent, 0.88))
    circle(p, cx, cy, 64, s().accent, fill=False, width=1.4)
    return p, "Mind map"


def call_log():
    p = page("Call log")
    table(p, TOP - 40, [("Date", 0), ("Name", 0.13), ("Number", 0.38), ("About", 0.58), ("Follow up", 0.86)], 20, row_h=30)
    return p, "Call log"


def timesheet():
    p = page("Timesheet", "Week of  ________________")
    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    top = TOP - 40
    w = RIGHT - LEFT
    cols = [("Day", 0), ("Start", 0.14), ("Break", 0.3), ("End", 0.46), ("Project", 0.62), ("Hours", 0.86)]
    p.rect(LEFT, top - 22, w, 22, fill=s().tab)
    for name, at in cols:
        label(p, LEFT + w * at + 6, top - 15, name, 9)
    rh = 52
    for i, d in enumerate(days):
        y = top - 22 - (i + 1) * rh
        p.text(LEFT + 6, y + rh / 2 - 3, d, 10, rgb=s().accent, bold=True)
        p.line(LEFT, y, RIGHT, y)
        for _, at in cols[1:]:
            p.line(LEFT + w * at, y, LEFT + w * at, y + rh, rgb=tint(s().rule, 0.3), width=0.6)
    y = top - 22 - 7 * rh
    p.rect(LEFT + w * 0.62, y - 34, w * 0.38, 34, fill=tint(s().accent, 0.9))
    label(p, LEFT + w * 0.62 + 8, y - 22, "Total hours", 10)
    label(p, LEFT, y - 70, "Notes")
    lines(p, LEFT, RIGHT, y - 94, int((y - 94 - BOTTOM) / 26) + 1)
    return p, "Timesheet"


def decision_log():
    p = page("Decision", False)
    field(p, LEFT, TOP - 24, "Decision", LEFT + 330)
    field(p, LEFT + 346, TOP - 24, "Date", RIGHT)
    y = TOP - 60
    label(p, LEFT, y, "Context")
    lines(p, LEFT, RIGHT, y - 24, 3)
    y -= 110
    label(p, LEFT, y, "Options")
    bottom = table(p, y - 10, [("Option", 0), ("Pros", 0.3), ("Cons", 0.65)], 4, row_h=44)
    label(p, LEFT, bottom - 26, "We chose")
    lines(p, LEFT, RIGHT, bottom - 50, 2)
    label(p, LEFT, bottom - 110, "Because")
    lines(p, LEFT, RIGHT, bottom - 134, 3)
    field(p, LEFT, BOTTOM + 30, "Review on", LEFT + 220)
    field(p, LEFT + 236, BOTTOM + 30, "Decided by", RIGHT)
    return p, "Decision log"


def retrospective():
    p = page("Retrospective", "Sprint or project  ________________")
    names = ("Went well", "To improve", "Ideas")
    xs, w = columns(p, LEFT, RIGHT, 3, gap=10)
    top = TOP - 44
    for x, name in zip(xs, names):
        p.rect(x, 250, w, top - 250, fill=tint(s().accent, 0.93))
        label(p, x + 10, top - 20, name, 11)
    label(p, LEFT, 224, "Actions")
    table(p, 214, [("Action", 0), ("Owner", 0.62), ("By", 0.82)], 6, row_h=28)
    return p, "Retrospective"


LAYOUTS = [project_planner, okrs, one_on_one, mind_map, call_log, timesheet, decision_log, retrospective]

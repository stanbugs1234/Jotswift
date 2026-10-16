"""Productivity pages: daily focus methods (1-3-5, Ivy Lee, eat the frog,
Pomodoro, time audit, shutdown, done list, distractions), projects and
meetings (charter, timeline, RACI, risks, agenda, actions, status, SWOT,
stakeholders) and goal setting (SMART, breakdown, 90 days, quarters,
12-week scorecard, wheel of life, vision, check-in, annual review).

Writing lines are 24pt or more apart throughout."""

import math

from layouts.kit import *  # noqa: F401,F403


def _hint(p, text, y=None):
    """A grey line of guidance under the title."""
    p.text(LEFT, TOP - 22 if y is None else y, text, 10, rgb=s().soft)


def _box_lines(p, x, y, w, h, title, prompt=None, kind="lines"):
    """A titled box filled with lines (or checkboxes) 26pt apart."""
    box(p, x, y, w, h, title)
    top = y + h - 44
    if prompt:
        p.text(x + 10, y + h - 32, prompt, 8.5, rgb=s().soft)
        top -= 10
    count = int((top - y - 8) / 26) + 1
    if count <= 0:
        return
    if kind == "checks":
        checkbox_rows(p, x + 10, x + w - 10, top, count, gap=26)
    else:
        lines(p, x + 10, x + w - 10, top, count, gap=26)


# Daily focus


def one_three_five():
    p = page("1-3-5 list")
    y = TOP - 48
    _hint(p, "One big thing, three medium things, five small things. That's a full day.", y + 4)
    y -= 16
    for name, n, gap in (("1 big thing", 1, 56), ("3 medium things", 3, 34), ("5 small things", 5, 28)):
        h = 34 + n * gap
        box(p, LEFT, y - h, RIGHT - LEFT, h, name)
        for k in range(n):
            ly = y - 40 - k * gap - (gap - 26) / 2
            p.rect(LEFT + 12, ly - 3, 12, 12, stroke=s().soft, width=1)
            p.line(LEFT + 34, ly - 4, RIGHT - 12, ly - 4)
        y -= h + 12
    _box_lines(p, LEFT, BOTTOM, RIGHT - LEFT, y - BOTTOM, "Notes")
    return p, "1-3-5 list"


def ivy_lee():
    p = page("Ivy Lee method", "For  ________________")
    _hint(p, "Tonight: write tomorrow's six most important tasks, in order. Tomorrow: work top to bottom.",
          TOP - 40)
    top = TOP - 60
    rh = 52
    for k in range(6):
        y = top - (k + 1) * rh
        p.rect(LEFT, y + 4, RIGHT - LEFT, rh - 8, stroke=s().rule, width=1)
        p.text(LEFT + 14, y + rh / 2 - 6, str(k + 1), 18, rgb=s().accent, bold=True)
        p.line(LEFT + 44, y + rh / 2 - 8, RIGHT - 90, y + rh / 2 - 8)
        p.text(RIGHT - 78, y + rh / 2 - 4, "Done", 8, rgb=s().soft)
        p.rect(RIGHT - 30, y + rh / 2 - 8, 14, 14, stroke=s().soft, width=1)
    y = top - 6 * rh - 14
    _box_lines(p, LEFT, BOTTOM, RIGHT - LEFT, y - BOTTOM, "Carry over to the next list",
               "Anything unfinished moves to tomorrow's six.", "checks")
    return p, "Ivy Lee method"


def eat_the_frog():
    p = page("Eat the frog")
    y = TOP - 48
    h = 210
    box(p, LEFT, y - h, RIGHT - LEFT, h, "Today's frog")
    p.text(LEFT + 12, y - 34, "The task I'm most likely to put off, done first.", 8.5, rgb=s().soft)
    p.line(LEFT + 12, y - 64, RIGHT - 12, y - 64)
    p.line(LEFT + 12, y - 92, RIGHT - 12, y - 92)
    fields(p, ["Why it matters", "First tiny step", "Started at", "Done at"], y - 122, gap=26,
           x0=LEFT + 12, x1=RIGHT - 12)
    y -= h + 12
    xs, w = columns(p, LEFT, RIGHT, 2)
    _box_lines(p, xs[0], BOTTOM, w, y - BOTTOM, "Then the rest of today", None, "checks")
    half = (y - BOTTOM - 12) / 2
    _box_lines(p, xs[1], BOTTOM + half + 12, w, half, "How it felt")
    _box_lines(p, xs[1], BOTTOM, w, half, "Tomorrow's frog")
    return p, "Eat the frog"


def pomodoro():
    p = page("Pomodoro tracker")
    _hint(p, "25 minutes on, 5 off. After four, take 20. Colour a tomato for each one.", TOP - 40)
    top = TOP - 58
    rows = 13
    rh = 34
    p.rect(LEFT, top - 22, RIGHT - LEFT, 22, fill=s().tab)
    label(p, LEFT + 6, top - 15, "Task", 9)
    label(p, LEFT + 286, top - 15, "Pomodoros", 9)
    for r in range(rows):
        y = top - 22 - (r + 1) * rh
        p.line(LEFT, y, RIGHT, y)
        for k in range(8):
            circle(p, LEFT + 300 + k * 28, y + rh / 2, 10, s().soft, fill=False, width=0.9)
    y = top - 22 - rows * rh - 14
    xs, w = columns(p, LEFT, RIGHT, 2)
    for x, name in zip(xs, ("Interruptions: from me", "Interruptions: from others")):
        _box_lines(p, x, BOTTOM, w, y - BOTTOM, name, "A tally mark each time, and what it was.")
    return p, "Pomodoro tracker"


def time_audit():
    p = page("Time audit")
    _hint(p, "Every half hour, jot what you did and its code. Add up the hours at the end.", TOP - 40)
    top = TOP - 58
    slots = 32  # 6:00 to 22:00
    x_split = LEFT + 330
    rh = (top - BOTTOM) / (slots / 2)
    for k in range(slots // 2):
        y = top - (k + 1) * rh
        h = 6 + k
        p.text(LEFT, y + rh - 12, f"{h % 12 or 12}{'am' if h < 12 else 'pm'}", 8, rgb=s().soft, bold=True)
        p.line(LEFT + 34, y + rh / 2, x_split - 50, y + rh / 2, rgb=tint(s().rule, 0.5), width=0.5)
        p.line(LEFT + 34, y, x_split - 50, y)
        p.rect(x_split - 44, y + 3, 30, rh - 6, stroke=s().rule, width=0.6)
    x0 = x_split
    box(p, x0, top - 250, RIGHT - x0, 250, "Codes")
    for k, code in enumerate(["D  Deep work", "M  Meetings", "A  Admin & email", "B  Breaks",
                              "S  Social media", "P  Personal", "", ""]):
        y = top - 44 - k * 26
        if code:
            p.text(x0 + 12, y, code, 9.5, rgb=s().ink)
        else:
            p.line(x0 + 12, y - 2, RIGHT - 12, y - 2)
    box(p, x0, BOTTOM, RIGHT - x0, top - 262 - BOTTOM, "Hours by code")
    for k in range(int((top - 262 - BOTTOM - 40) / 26) + 1):
        y = top - 262 - 44 - k * 26
        p.line(x0 + 12, y, x0 + 60, y)
        p.line(x0 + 72, y, RIGHT - 12, y)
    return p, "Time audit"


def shutdown():
    p = page("Daily shutdown")
    y = TOP - 48
    steps = ["Inbox and messages cleared or noted", "Every open loop written down",
             "Calendar for tomorrow checked", "Tomorrow's top 3 chosen", "Desk and tabs tidied",
             "Say it: \"Shutdown complete\""]
    h = 36 + len(steps) * 28
    box(p, LEFT, y - h, RIGHT - LEFT, h, "Shutdown checklist")
    for k, step in enumerate(steps):
        ly = y - 44 - k * 28
        p.rect(LEFT + 12, ly - 3, 12, 12, stroke=s().soft, width=1)
        p.text(LEFT + 34, ly - 1, step, 10.5, rgb=s().ink)
    y -= h + 12
    xs, w = columns(p, LEFT, RIGHT, 2)
    half = (y - BOTTOM - 12) / 2
    _box_lines(p, xs[0], BOTTOM + half + 12, w, half, "Today's wins")
    _box_lines(p, xs[1], BOTTOM + half + 12, w, half, "Loose ends")
    _box_lines(p, LEFT, BOTTOM, RIGHT - LEFT, half, "Tomorrow's top 3", None, "checks")
    return p, "Daily shutdown"


def done_list():
    p = page("Done list")
    _hint(p, "Everything you finished today, big or small. Proof the day counted.", TOP - 40)
    numbered(p, LEFT, RIGHT, TOP - 76, 23, gap=27)
    return p, "Done list"


def distractions():
    p = page("Distraction log")
    _hint(p, "Notice what pulls you away, then plan around it.", TOP - 40)
    table(p, TOP - 56, [("Time", 0), ("What pulled me away", 0.14), ("Trigger", 0.52), ("Next time I'll", 0.74)],
          22, row_h=27)
    return p, "Distraction log"


# Projects and meetings


def project_charter():
    p = page("Project charter", False)
    field(p, LEFT, TOP - 26, "Project", LEFT + 330)
    field(p, LEFT + 346, TOP - 26, "Owner", RIGHT)
    field(p, LEFT, TOP - 54, "Start", LEFT + 160)
    field(p, LEFT + 176, TOP - 54, "Deadline", LEFT + 346)
    field(p, LEFT + 362, TOP - 54, "Budget", RIGHT)
    y = TOP - 76
    _box_lines(p, LEFT, y - 100, RIGHT - LEFT, 100, "Goal", "What will be true when this is done?")
    y -= 112
    xs, w = columns(p, LEFT, RIGHT, 2)
    _box_lines(p, xs[0], y - 150, w, 150, "In scope", None, "checks")
    _box_lines(p, xs[1], y - 150, w, 150, "Out of scope", None, "checks")
    y -= 162
    _box_lines(p, xs[0], BOTTOM, w, y - BOTTOM, "Success criteria", None, "checks")
    _box_lines(p, xs[1], BOTTOM, w, y - BOTTOM, "Stakeholders")
    return p, "Project charter"


def timeline():
    p = page("12-week timeline", "Project  ________________________      Starts  __________")
    name_w = 150
    top = TOP - 50
    cw = (RIGHT - LEFT - name_w) / 12
    p.rect(LEFT, top - 22, RIGHT - LEFT, 22, fill=s().tab)
    label(p, LEFT + 6, top - 15, "Task", 9)
    for k in range(12):
        x = LEFT + name_w + k * cw
        p.text(x + cw / 2, top - 15, f"W{k + 1}", 8.5, rgb=s().accent, bold=True, center=True)
    rows = int((top - 22 - BOTTOM - 40) / 28)
    for r in range(rows + 1):
        y = top - 22 - r * 28
        p.line(LEFT, y, RIGHT, y, rgb=s().rule if r else s().rule)
    for k in range(13):
        x = LEFT + name_w + k * cw
        p.line(x, top - 22, x, top - 22 - rows * 28, rgb=tint(s().rule, 0.3), width=0.6)
    y = top - 22 - rows * 28 - 18
    p.text(LEFT, y, "Shade the weeks each task runs. Mark milestones with a diamond.", 9, rgb=s().soft)
    return p, "12-week timeline"


def raci():
    p = page("RACI matrix", "Project  ________________________")
    _hint(p, "R  Responsible   A  Accountable (one per task)   C  Consulted   I  Informed", TOP - 40)
    cols = [("Task", 0)] + [("", 0.4 + k * 0.1) for k in range(6)]
    bottom = table(p, TOP - 56, cols, 21, row_h=27)
    for k in range(6):
        x = LEFT + (RIGHT - LEFT) * (0.4 + k * 0.1)
        p.line(x + 6, TOP - 56 - 15, x + (RIGHT - LEFT) * 0.1 - 6, TOP - 56 - 15, rgb=s().soft, width=0.6)
    p.text(LEFT, bottom - 16, "Write a person or team at the top of each column.", 9, rgb=s().soft)
    return p, "RACI matrix"


def risk_log():
    p = page("Risk log", "Project  ________________________")
    _hint(p, "Likelihood and impact: L (low), M (medium), H (high).", TOP - 40)
    table(p, TOP - 56, [("Risk", 0), ("Likely", 0.34), ("Impact", 0.44), ("Plan to reduce it", 0.54),
                        ("Owner", 0.86)], 21, row_h=28)
    return p, "Risk log"


def agenda():
    p = page("Meeting agenda", False)
    field(p, LEFT, TOP - 26, "Meeting", LEFT + 330)
    field(p, LEFT + 346, TOP - 26, "Date", RIGHT)
    field(p, LEFT, TOP - 54, "Goal", RIGHT)
    field(p, LEFT, TOP - 82, "Attendees", RIGHT)
    bottom = table(p, TOP - 100, [("Time", 0), ("Topic", 0.14), ("Lead", 0.72), ("Mins", 0.88)], 9, row_h=28)
    y = bottom - 12
    xs, w = columns(p, LEFT, RIGHT, 2)
    _box_lines(p, xs[0], BOTTOM, w, y - BOTTOM, "Decisions")
    _box_lines(p, xs[1], BOTTOM, w, y - BOTTOM, "Parking lot")
    return p, "Meeting agenda"


def action_items():
    p = page("Action items")
    table(p, TOP - 44, [("Action", 0), ("Owner", 0.5), ("Due", 0.68), ("Status", 0.82)], 22, row_h=28,
          check=True)
    return p, "Action items"


def status_report():
    p = page("Weekly status", "Project  ________________________      Week of  __________")
    y = TOP - 48
    label(p, LEFT, y - 2, "Overall", 11)
    for k, word in enumerate(["On track", "At risk", "Off track"]):
        x = LEFT + 80 + k * 120
        circle(p, x + 8, y + 2, 8, s().soft, fill=False, width=1)
        p.text(x + 22, y - 2, word, 10, rgb=s().ink)
    y -= 22
    xs, w = columns(p, LEFT, RIGHT, 2)
    h = (y - BOTTOM - 24) / 3
    _box_lines(p, xs[0], y - h, w, h, "Done this week", None, "checks")
    _box_lines(p, xs[1], y - h, w, h, "Next week", None, "checks")
    y -= h + 12
    _box_lines(p, xs[0], y - h, w, h, "Blockers")
    _box_lines(p, xs[1], y - h, w, h, "Help needed")
    y -= h + 12
    _box_lines(p, LEFT, BOTTOM, RIGHT - LEFT, y - BOTTOM, "Notes for the team")
    return p, "Weekly status report"


def swot():
    p = page("SWOT", "For  ________________________")
    top = TOP - 44
    gap = 10
    w = (RIGHT - LEFT - gap) / 2
    h = (top - BOTTOM - gap) / 2
    cells = [("Strengths", "Inside: what we do well"), ("Weaknesses", "Inside: what holds us back"),
             ("Opportunities", "Outside: what we could use"), ("Threats", "Outside: what could hurt us")]
    for i, (name, hint) in enumerate(cells):
        x = LEFT + (i % 2) * (w + gap)
        y = top - (i // 2 + 1) * h - (i // 2) * gap
        _box_lines(p, x, y, w, h, name, hint)
    return p, "SWOT"


def stakeholders():
    p = page("Stakeholder map", "Project  ________________________")
    top = TOP - 44
    size = 300
    x0, y0 = LEFT + 26, top - size
    gap = 6
    q = (size - gap) / 2
    cells = [("Keep satisfied", 0), ("Manage closely", 1), ("Monitor", 2), ("Keep informed", 3)]
    for name, i in cells:
        x = x0 + (i % 2) * (q + gap)
        y = y0 + (1 - i // 2) * (q + gap)
        p.rect(x, y, q, q, fill=tint(s().accent, 0.92) if i == 1 else None, stroke=s().rule, width=1)
        p.text(x + 8, y + q - 16, name, 9, rgb=s().accent, bold=True)
    p.text(x0 + size / 2, y0 - 16, "Interest  ->", 9, rgb=s().soft, center=True)
    p.ops.append(f"q 0 1 -1 0 {x0 - 10:.1f} {y0 + size / 2 - 30:.1f} cm")
    p.text(0, 0, "Influence  ->", 9, rgb=s().soft)
    p.ops.append("Q")
    side = x0 + size + 16
    _box_lines(p, side, y0, RIGHT - side, size, "Who's who")
    y = y0 - 32
    table(p, y, [("Stakeholder", 0), ("Wants", 0.3), ("How we'll keep them on board", 0.58)],
          int((y - 22 - BOTTOM) / 28), row_h=28)
    return p, "Stakeholder map"


# Goal setting


def smart_goal():
    p = page("SMART goal")
    field(p, LEFT, TOP - 52, "My goal", RIGHT)
    p.line(LEFT, TOP - 80, RIGHT, TOP - 80)
    y = TOP - 96
    letters = [("S", "Specific", "What exactly, where and with whom?"),
               ("M", "Measurable", "How will I know it's done?"),
               ("A", "Achievable", "What will I need? Is it realistic?"),
               ("R", "Relevant", "Why does it matter now?"),
               ("T", "Time-bound", "By when? What are the checkpoints?")]
    rh = 74
    for letter, word, hint in letters:
        p.rect(LEFT, y - rh + 6, 44, rh - 6, fill=s().tab)
        p.text(LEFT + 22, y - rh / 2 - 6, letter, 24, rgb=s().accent, bold=True, center=True)
        p.text(LEFT + 56, y - 14, word, 10.5, rgb=s().accent, bold=True)
        p.text(LEFT + 56 + mp_w(word) + 10, y - 14, hint, 8.5, rgb=s().soft)
        lines(p, LEFT + 56, RIGHT, y - 38, 2, gap=26)
        y -= rh
    xs, w = columns(p, LEFT, RIGHT, 2)
    _box_lines(p, xs[0], BOTTOM, w, y - BOTTOM - 6, "Obstacles & how I'll handle them")
    _box_lines(p, xs[1], BOTTOM, w, y - BOTTOM - 6, "My reward")
    return p, "SMART goal"


def mp_w(text, size=10.5):
    import make_planner as mp
    return mp.text_width(text, size)


def goal_breakdown():
    p = page("Goal breakdown", False)
    p.rect(LEFT, TOP - 74, RIGHT - LEFT, 46, fill=s().tab)
    label(p, LEFT + 12, TOP - 46, "Goal", 11)
    p.line(LEFT + 52, TOP - 48, RIGHT - 12, TOP - 48)
    p.text(LEFT + 12, TOP - 66, "Done by", 9, rgb=s().soft, bold=True)
    p.line(LEFT + 60, TOP - 68, LEFT + 220, TOP - 68)
    top = TOP - 90
    xs, w = columns(p, LEFT, RIGHT, 3)
    for k, x in enumerate(xs):
        p.line(x + w / 2, TOP - 74, x + w / 2, top, rgb=s().rule, width=1)
        box(p, x, BOTTOM, w, top - BOTTOM, f"Milestone {k + 1}")
        p.line(x + 10, top - 46, x + w - 10, top - 46)
        p.text(x + 10, top - 64, "By", 9, rgb=s().soft, bold=True)
        p.line(x + 28, top - 66, x + w - 10, top - 66)
        p.text(x + 10, top - 90, "Steps", 9, rgb=s().soft, bold=True)
        checkbox_rows(p, x + 10, x + w - 10, top - 114, int((top - 114 - BOTTOM - 8) / 26) + 1, gap=26)
    return p, "Goal breakdown"


def ninety_days():
    p = page("90-day plan", "Starts  ______________      Goal  ______________________________")
    top = TOP - 44
    xs, w = columns(p, LEFT, RIGHT, 3)
    h = 220
    for k, x in enumerate(xs):
        _box_lines(p, x, top - h, w, h, f"Month {k + 1}", "Milestone and key steps", "checks")
    y = top - h - 28
    label(p, LEFT, y, "Weekly check-ins", 11)
    y -= 12
    rh = (y - BOTTOM) / 13
    for k in range(13):
        ry = y - (k + 1) * rh
        p.text(LEFT, ry + rh / 2 - 3, f"Week {k + 1}", 8.5, rgb=s().accent, bold=True)
        p.line(LEFT + 52, ry + 4, RIGHT - 60, ry + 4)
        bar(p, RIGHT - 52, ry + 6, 52, min(10, rh - 8), 5)
    return p, "90-day plan"


def quarterly_goals():
    p = page("Quarterly goals", "Year  __________")
    top = TOP - 44
    gap = 10
    w = (RIGHT - LEFT - gap) / 2
    h = (top - BOTTOM - gap) / 2
    for i in range(4):
        x = LEFT + (i % 2) * (w + gap)
        y = top - (i // 2 + 1) * h - (i // 2) * gap
        box(p, x, y, w, h, f"Q{i + 1}")
        bar(p, x + w - 130, y + h - 22, 120, 10, 10)
        checkbox_rows(p, x + 10, x + w - 10, y + h - 50, int((h - 90) / 26) + 1, gap=26)
        p.text(x + 10, y + 14, "Result", 9, rgb=s().soft, bold=True)
        p.line(x + 50, y + 12, x + w - 10, y + 12)
    return p, "Quarterly goals"


def scorecard():
    p = page("12-week scorecard", "Goal  ______________________________")
    _hint(p, "Tick each tactic done that week. Score = ticks / tactics. 85% or more is a win.", TOP - 40)
    name_w = 170
    top = TOP - 58
    cw = (RIGHT - LEFT - name_w) / 12
    p.rect(LEFT, top - 22, RIGHT - LEFT, 22, fill=s().tab)
    label(p, LEFT + 6, top - 15, "Tactic", 9)
    for k in range(12):
        p.text(LEFT + name_w + k * cw + cw / 2, top - 15, f"W{k + 1}", 8.5, rgb=s().accent, bold=True, center=True)
    rows = 15
    rh = 28
    for r in range(rows):
        y = top - 22 - (r + 1) * rh
        p.line(LEFT, y, RIGHT, y)
        for k in range(12):
            p.rect(LEFT + name_w + k * cw + cw / 2 - 6, y + rh / 2 - 6, 12, 12, stroke=s().rule, width=0.7)
    y = top - 22 - rows * rh
    p.rect(LEFT, y - 30, RIGHT - LEFT, 30, fill=s().tab)
    label(p, LEFT + 6, y - 19, "Score %", 9)
    for k in range(13):
        x = LEFT + name_w + k * cw
        p.line(x, top - 22, x, y - 30, rgb=tint(s().rule, 0.3), width=0.6)
    return p, "12-week scorecard"


def wheel_of_life():
    p = page("Wheel of life")
    _hint(p, "Rate each area 1-10 by shading from the centre out. Then pick two to focus on.", TOP - 40)
    areas = ["Health", "Career", "Money", "Relationships", "Family & friends", "Fun", "Growth", "Home"]
    cx, cy, r = (LEFT + RIGHT) / 2, TOP - 260, 190
    for ring in range(1, 11):
        circle(p, cx, cy, r * ring / 10, tint(s().rule, 0.2 if ring < 10 else 0), fill=False,
               width=0.5 if ring < 10 else 1.2)
    for k, name in enumerate(areas):
        a = math.pi / 2 - k * 2 * math.pi / 8
        p.line(cx, cy, cx + r * math.cos(a), cy + r * math.sin(a), rgb=s().rule, width=0.8)
        mid = a - math.pi / 8
        lx, ly = cx + (r + 22) * math.cos(mid), cy + (r + 22) * math.sin(mid)
        p.text(lx, ly - 3, name, 9.5, rgb=s().accent, bold=True, center=True)
    y = cy - r - 46
    xs, w = columns(p, LEFT, RIGHT, 2)
    _box_lines(p, xs[0], BOTTOM, w, y - BOTTOM, "Focus area 1", "What would a 10 look like?")
    _box_lines(p, xs[1], BOTTOM, w, y - BOTTOM, "Focus area 2", "What would a 10 look like?")
    return p, "Wheel of life"


def vision_values():
    p = page("Vision & values")
    y = TOP - 48
    _box_lines(p, LEFT, y - 230, RIGHT - LEFT, 230, "Three years from now",
               "Describe an ordinary day, as if it's already true.")
    y -= 242
    xs, w = columns(p, LEFT, RIGHT, 2)
    h = (y - BOTTOM - 12) / 2
    box(p, xs[0], y - h, w, h, "My core values")
    numbered(p, xs[0] + 10, xs[0] + w - 10, y - 48, int((h - 48) / 26) + 1, gap=26)
    _box_lines(p, xs[1], y - h, w, h, "I say no to", None, "checks")
    _box_lines(p, LEFT, BOTTOM, RIGHT - LEFT, h, "This year, that means")
    return p, "Vision & values"


def check_in():
    p = page("Accountability check-in", "Week of  ________________")
    y = TOP - 48
    label(p, LEFT, y - 2, "This week I kept my promises to myself", 10.5)
    for k in range(10):
        circle(p, LEFT + 290 + k * 22, y + 2, 8, s().soft, fill=False, width=0.9)
        p.text(LEFT + 290 + k * 22, y - 1, str(k + 1), 6.5, rgb=s().soft, center=True)
    y -= 22
    xs, w = columns(p, LEFT, RIGHT, 2)
    h = (y - BOTTOM - 24) / 3
    _box_lines(p, xs[0], y - h, w, h, "Wins")
    _box_lines(p, xs[1], y - h, w, h, "Misses")
    y -= h + 12
    _box_lines(p, xs[0], y - h, w, h, "What got in the way")
    _box_lines(p, xs[1], y - h, w, h, "What I'll adjust")
    y -= h + 12
    _box_lines(p, LEFT, BOTTOM, RIGHT - LEFT, y - BOTTOM, "Next week I commit to", None, "checks")
    return p, "Accountability check-in"


def annual_review():
    p = page("Annual review", "Year  __________")
    y = TOP - 44
    xs, w = columns(p, LEFT, RIGHT, 2)
    prompts = [("Best moments", None), ("Hardest moments", None), ("Biggest lessons", None),
               ("Goals reached", None), ("By the numbers", "Money, books, miles, anything you track"),
               ("Let go of", None)]
    band = 120
    h = (y - BOTTOM - band - 12 - 24) / 3
    for k, (name, hint) in enumerate(prompts):
        x = xs[k % 2]
        ty = y - (k // 2 + 1) * h - (k // 2) * 12
        _box_lines(p, x, ty, w, h, name, hint)
    p.rect(LEFT, BOTTOM, RIGHT - LEFT, band, fill=s().tab)
    label(p, LEFT + 12, BOTTOM + band - 24, "My word for next year", 11)
    p.line(LEFT + 12, BOTTOM + band - 64, LEFT + 240, BOTTOM + band - 64)
    label(p, LEFT + 270, BOTTOM + band - 24, "Top 3 goals", 11)
    numbered(p, LEFT + 270, RIGHT - 12, BOTTOM + band - 50, 3, gap=26)
    return p, "Annual review"

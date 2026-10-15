"""Single-page layouts for collection page packs.

Every layout draws in the current style (see make_planner.use_style), so
one layout comes out in every collection's look. pack() returns the pages
and the template.json that lists them.
"""

import make_planner as mp
from make_planner import H, W, Page, circle, header, tint

LEFT, RIGHT = 48, W - 48
TOP = H - 72  # title baseline


def _s():
    """The current style (make_planner.S is rebound by use_style)."""
    return mp.S


def label(p, x, y, text, size=11):
    p.text(x, y, text, size, rgb=_s().accent, bold=True)


def lines(p, x0, x1, y_top, count, gap=26):
    for i in range(count):
        p.line(x0, y_top - i * gap, x1, y_top - i * gap)


def checkbox_rows(p, x0, x1, y_top, count, gap=28):
    for i in range(count):
        y = y_top - i * gap
        p.rect(x0, y - 3, 12, 12, stroke=_s().soft, width=1)
        p.line(x0 + 22, y - 4, x1, y - 4)


def box(p, x, y, w, h, title=None):
    p.rect(x, y, w, h, stroke=_s().rule, width=1)
    if title:
        label(p, x + 10, y + h - 18, title, 10)


def date_line(p, text="Date"):
    p.text(LEFT, TOP - 22, f"{text}  ________________", 11, rgb=_s().soft)


# Planning


def daily():
    p = Page()
    header(p, LEFT, TOP, "Today", 30)
    date_line(p)
    mid = LEFT + (RIGHT - LEFT) * 0.55
    label(p, LEFT, TOP - 56, "Schedule")
    for i, hour in enumerate(range(6, 22)):
        y = TOP - 80 - i * 30
        h12 = hour % 12 or 12
        p.text(LEFT, y + 4, f"{h12}{'am' if hour < 12 else 'pm'}", 8, rgb=_s().soft)
        p.line(LEFT + 30, y, mid - 16, y)
    label(p, mid, TOP - 56, "Top 3")
    checkbox_rows(p, mid, RIGHT, TOP - 82, 3, gap=30)
    label(p, mid, TOP - 190, "To-do")
    checkbox_rows(p, mid, RIGHT, TOP - 216, 8)
    label(p, mid, TOP - 460, "Notes")
    lines(p, mid, RIGHT, TOP - 484, 7)
    return p, "Daily planner"


def time_blocks():
    """ADHD-friendly: big blocks, one focus, a short list."""
    p = Page()
    header(p, LEFT, TOP, "Time blocks", 30)
    date_line(p)
    label(p, LEFT, TOP - 56, "One thing that matters today")
    p.rect(LEFT, TOP - 110, RIGHT - LEFT, 40, fill=tint(_s().accent, 0.88))
    blocks = ["Morning", "Midday", "Afternoon", "Evening"]
    bh = 118
    for i, name in enumerate(blocks):
        y = TOP - 140 - (i + 1) * (bh + 10)
        box(p, LEFT, y, RIGHT - LEFT, bh, name)
        for k in range(3):
            p.rect(LEFT + 12, y + bh - 46 - k * 26, 10, 10, stroke=_s().soft, width=1)
            p.line(LEFT + 30, y + bh - 47 - k * 26, RIGHT - 12, y + bh - 47 - k * 26)
    return p, "Time blocks"


def weekly():
    p = Page()
    header(p, LEFT, TOP, "This week", 30)
    p.text(LEFT, TOP - 22, "Week of  ________________", 11, rgb=_s().soft)
    days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    top = TOP - 44
    rh = (top - 56) / 7
    for i, d in enumerate(days):
        y = top - (i + 1) * rh
        p.rect(LEFT, y, 92, rh, fill=_s().tab)
        label(p, LEFT + 8, y + rh - 18, d, 10)
        p.rect(LEFT, y, RIGHT - LEFT, rh, stroke=_s().rule, width=0.8)
        for k in range(1, int(rh / 22)):
            p.line(LEFT + 102, y + rh - k * 22, RIGHT - 8, y + rh - k * 22)
    return p, "Weekly (vertical)"


def monthly():
    p = Page()
    header(p, LEFT, TOP, "Month", 30)
    p.text(LEFT, TOP - 22, "Month  ________________", 11, rgb=_s().soft)
    top = TOP - 52
    cw = (RIGHT - LEFT) / 7
    for i, d in enumerate(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]):
        p.text(LEFT + i * cw + 6, top + 6, d, 9, rgb=_s().soft, bold=True)
    rh = (top - 200) / 6
    for r in range(6):
        for c in range(7):
            p.rect(LEFT + c * cw, top - (r + 1) * rh, cw, rh, stroke=_s().rule, width=0.8)
    label(p, LEFT, 172, "Goals this month")
    checkbox_rows(p, LEFT, RIGHT, 148, 4)
    return p, "Monthly (undated)"


def goals():
    p = Page()
    header(p, LEFT, TOP, "Goals", 30)
    y = TOP - 40
    for i in range(3):
        bh = 190
        box(p, LEFT, y - bh, RIGHT - LEFT, bh, f"Goal {i + 1}")
        p.text(LEFT + 12, y - 44, "Why it matters", 9, rgb=_s().soft)
        p.line(LEFT + 90, y - 46, RIGHT - 12, y - 46)
        p.text(LEFT + 12, y - 72, "Steps", 9, rgb=_s().soft)
        checkbox_rows(p, LEFT + 12, RIGHT - 12, y - 96, 3, gap=26)
        p.text(LEFT + 12, y - bh + 14, "Done by", 9, rgb=_s().soft)
        p.line(LEFT + 60, y - bh + 12, LEFT + 220, y - bh + 12)
        y -= bh + 14
    return p, "Goals"


def weekly_review():
    p = Page()
    header(p, LEFT, TOP, "Weekly review", 30)
    p.text(LEFT, TOP - 22, "Week of  ________________", 11, rgb=_s().soft)
    prompts = ["What went well", "What was hard", "What I learned", "Next week's focus"]
    y = TOP - 48
    bh = (y - 50) / 4 - 10
    for t in prompts:
        box(p, LEFT, y - bh, RIGHT - LEFT, bh, t)
        lines(p, LEFT + 12, RIGHT - 12, y - 44, int((bh - 40) / 24), gap=24)
        y -= bh + 10
    return p, "Weekly review"


# To-do


def todo():
    p = Page()
    header(p, LEFT, TOP, "To-do", 30)
    date_line(p)
    checkbox_rows(p, LEFT, RIGHT, TOP - 60, 22, gap=29)
    return p, "To-do list"


def priority_matrix():
    p = Page()
    header(p, LEFT, TOP, "Priorities", 30)
    top, gap = TOP - 40, 10
    w = (RIGHT - LEFT - gap) / 2
    h = (top - 50 - gap) / 2
    cells = [("Urgent & important", "Do now"), ("Important, not urgent", "Plan"),
             ("Urgent, not important", "Hand off"), ("Neither", "Drop")]
    for i, (name, action) in enumerate(cells):
        x = LEFT + (i % 2) * (w + gap)
        y = top - (i // 2 + 1) * h - (i // 2) * gap
        if i == 0:
            p.rect(x, y, w, h, fill=tint(_s().accent, 0.9))
        box(p, x, y, w, h, name)
        p.text(x + w - 10, y + h - 18, action, 9, rgb=_s().soft, right=True)
        checkbox_rows(p, x + 10, x + w - 10, y + h - 44, int((h - 50) / 26), gap=26)
    return p, "Priority matrix"


def kanban():
    p = Page()
    header(p, LEFT, TOP, "Board", 30)
    cols = ["To do", "Doing", "Done"]
    gap = 10
    w = (RIGHT - LEFT - 2 * gap) / 3
    top = TOP - 40
    for i, name in enumerate(cols):
        x = LEFT + i * (w + gap)
        p.rect(x, top - 30, w, 30, fill=_s().tab)
        label(p, x + 10, top - 20, name, 11)
        p.rect(x, 50, w, top - 50, stroke=_s().rule, width=1)
        for k in range(8):
            y = top - 44 - k * 76
            if y - 62 < 56:
                break
            p.rect(x + 8, y - 62, w - 16, 62, stroke=tint(_s().rule, 0.3), width=0.6)
    return p, "Kanban board"


def brain_dump():
    p = Page()
    header(p, LEFT, TOP, "Brain dump", 30)
    p.text(LEFT, TOP - 22, "Write it all down, sort it later.", 11, rgb=_s().soft)
    for r in range(28):
        for c in range(19):
            circle(p, LEFT + 4 + c * 27.5, TOP - 52 - r * 23, 0.9, _s().rule)
    return p, "Brain dump"


# Trackers


def habit_tracker():
    p = Page()
    header(p, LEFT, TOP, "Habits", 30)
    p.text(LEFT, TOP - 22, "Month  ________________", 11, rgb=_s().soft)
    days, name_w = 31, 120
    cw = (RIGHT - LEFT - name_w) / days
    top = TOP - 60
    for d in range(days):
        p.text(LEFT + name_w + d * cw + cw / 2, top + 6, str(d + 1), 6.5, rgb=_s().soft, center=True)
    for r in range(16):
        y = top - (r + 1) * 30
        p.line(LEFT, y, LEFT + name_w - 6, y)
        for d in range(days):
            circle(p, LEFT + name_w + d * cw + cw / 2, y + 8, cw * 0.36, _s().rule, fill=False, width=0.6)
    return p, "Habit tracker"


def mood_tracker():
    p = Page()
    header(p, LEFT, TOP, "Mood", 30)
    p.text(LEFT, TOP - 22, "Month  ________________", 11, rgb=_s().soft)
    moods = ["Great", "Good", "Okay", "Low", "Rough"]
    for i, m in enumerate(moods):
        x = LEFT + i * 100
        circle(p, x + 8, TOP - 52, 7, tint(_s().accent, 0.15 + i * 0.17))
        p.text(x + 22, TOP - 56, m, 10, rgb=_s().ink)
    top = TOP - 90
    cols, size = 7, (RIGHT - LEFT) / 7
    for d in range(31):
        cx = LEFT + (d % cols) * size + size / 2
        cy = top - (d // cols) * size - size / 2
        circle(p, cx, cy, size * 0.36, _s().rule, fill=False, width=1)
        p.text(cx, cy - 3.5, str(d + 1), 9, rgb=_s().soft, center=True)
    label(p, LEFT, 150, "Notes")
    lines(p, LEFT, RIGHT, 126, 3)
    return p, "Mood tracker"


def water_sleep():
    p = Page()
    header(p, LEFT, TOP, "Water & sleep", 30)
    p.text(LEFT, TOP - 22, "Week of  ________________", 11, rgb=_s().soft)
    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    label(p, LEFT, TOP - 60, "Glasses of water")
    for i, d in enumerate(days):
        y = TOP - 90 - i * 30
        p.text(LEFT, y, d, 10, rgb=_s().soft)
        for g in range(8):
            p.rect(LEFT + 50 + g * 30, y - 4, 18, 18, stroke=_s().rule, width=1)
    label(p, LEFT, TOP - 330, "Hours of sleep")
    for i, d in enumerate(days):
        y = TOP - 360 - i * 30
        p.text(LEFT, y, d, 10, rgb=_s().soft)
        for h in range(12):
            circle(p, LEFT + 60 + h * 28, y + 4, 8, _s().rule, fill=False)
            p.text(LEFT + 60 + h * 28, y + 1, str(h + 1), 6.5, rgb=_s().soft, center=True)
    return p, "Water & sleep"


def reading_log():
    p = Page()
    header(p, LEFT, TOP, "Reading log", 30)
    cols = [("Title", 0), ("Author", 0.42), ("Started", 0.66), ("Finished", 0.8), ("Rating", 0.93)]
    top = TOP - 44
    span = RIGHT - LEFT
    p.rect(LEFT, top - 24, span, 24, fill=_s().tab)
    for name, at in cols:
        label(p, LEFT + span * at + 6, top - 16, name, 9)
    for r in range(22):
        y = top - 24 - (r + 1) * 28
        p.line(LEFT, y, RIGHT, y)
    return p, "Reading log"


def budget():
    p = Page()
    header(p, LEFT, TOP, "Budget", 30)
    p.text(LEFT, TOP - 22, "Month  ________________", 11, rgb=_s().soft)
    y = TOP - 50
    for name in ["Income", "Bills", "Spending", "Savings"]:
        box(p, LEFT, y - 26, RIGHT - LEFT, 26)
        label(p, LEFT + 10, y - 17, name, 10)
        p.text(RIGHT - 120, y - 17, "$", 10, rgb=_s().soft)
        y -= 34
    label(p, LEFT, y - 14, "Expenses")
    top = y - 30
    p.rect(LEFT, top - 22, RIGHT - LEFT, 22, fill=_s().tab)
    for name, at in [("Date", 0), ("What", 0.18), ("Category", 0.62), ("Amount", 0.84)]:
        label(p, LEFT + (RIGHT - LEFT) * at + 6, top - 15, name, 9)
    for r in range(16):
        p.line(LEFT, top - 22 - (r + 1) * 24, RIGHT, top - 22 - (r + 1) * 24)
    return p, "Budget"


def meal_plan():
    p = Page()
    header(p, LEFT, TOP, "Meal plan", 30)
    p.text(LEFT, TOP - 22, "Week of  ________________", 11, rgb=_s().soft)
    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    meals = ["Breakfast", "Lunch", "Dinner"]
    top, dw = TOP - 50, 46
    mw = (RIGHT - LEFT - dw - 170) / 3
    for i, m in enumerate(meals):
        label(p, LEFT + dw + i * mw + 6, top - 4, m, 9)
    rh = 52
    for r, d in enumerate(days):
        y = top - 14 - (r + 1) * rh
        p.text(LEFT, y + rh / 2 - 4, d, 10, rgb=_s().soft, bold=True)
        for i in range(3):
            p.rect(LEFT + dw + i * mw, y, mw, rh, stroke=_s().rule, width=0.8)
    gx = RIGHT - 160
    p.rect(gx, top - 14 - 7 * rh, 160, 7 * rh + 14, fill=_s().tab)
    label(p, gx + 10, top - 4, "Groceries", 10)
    checkbox_rows(p, gx + 10, RIGHT - 10, top - 32, 13, gap=26)
    return p, "Meal plan"


def workout_log():
    p = Page()
    header(p, LEFT, TOP, "Workout", 30)
    date_line(p)
    top = TOP - 50
    cols = [("Exercise", 0), ("Sets", 0.5), ("Reps", 0.63), ("Weight", 0.76), ("Notes", 0.88)]
    p.rect(LEFT, top - 22, RIGHT - LEFT, 22, fill=_s().tab)
    for name, at in cols:
        label(p, LEFT + (RIGHT - LEFT) * at + 6, top - 15, name, 9)
    for r in range(16):
        p.line(LEFT, top - 22 - (r + 1) * 26, RIGHT, top - 22 - (r + 1) * 26)
    label(p, LEFT, 130, "How it felt")
    lines(p, LEFT, RIGHT, 106, 3)
    return p, "Workout log"


def gratitude():
    p = Page()
    header(p, LEFT, TOP, "Gratitude", 30)
    date_line(p)
    y = TOP - 60
    for i in range(3):
        label(p, LEFT, y, f"Today I'm grateful for ({i + 1})", 10)
        lines(p, LEFT, RIGHT, y - 22, 2)
        y -= 76
    label(p, LEFT, y, "A small win")
    lines(p, LEFT, RIGHT, y - 22, 2)
    y -= 76
    label(p, LEFT, y, "Tomorrow I look forward to")
    lines(p, LEFT, RIGHT, y - 22, 3)
    return p, "Gratitude journal"


# Study and notes


def cornell():
    p = Page()
    header(p, LEFT, TOP, "Notes", 30)
    p.text(LEFT, TOP - 22, "Topic  ____________________   Date  __________", 11, rgb=_s().soft)
    cue = LEFT + 150
    bottom = 150
    p.line(cue, TOP - 40, cue, bottom, rgb=_s().accent, width=1)
    p.line(LEFT, bottom, RIGHT, bottom, rgb=_s().accent, width=1)
    label(p, LEFT, TOP - 56, "Cues", 10)
    lines(p, cue + 10, RIGHT, TOP - 60, int((TOP - 60 - bottom) / 26))
    label(p, LEFT, bottom - 20, "Summary", 10)
    lines(p, LEFT, RIGHT, bottom - 44, 3)
    return p, "Cornell notes"


def class_schedule():
    p = Page()
    header(p, LEFT, TOP, "Class schedule", 30)
    days = ["Mon", "Tue", "Wed", "Thu", "Fri"]
    tw = 44
    cw = (RIGHT - LEFT - tw) / 5
    top = TOP - 40
    for i, d in enumerate(days):
        p.rect(LEFT + tw + i * cw, top - 24, cw, 24, fill=_s().tab)
        label(p, LEFT + tw + i * cw + 8, top - 16, d, 10)
    rh = (top - 24 - 50) / 12
    for r in range(12):
        y = top - 24 - (r + 1) * rh
        hour = 7 + r
        p.text(LEFT, y + rh - 12, f"{hour % 12 or 12}{'am' if hour < 12 else 'pm'}", 8, rgb=_s().soft)
        for i in range(5):
            p.rect(LEFT + tw + i * cw, y, cw, rh, stroke=_s().rule, width=0.6)
    return p, "Class schedule"


def assignments():
    p = Page()
    header(p, LEFT, TOP, "Assignments", 30)
    top = TOP - 44
    cols = [("Done", 0), ("Class", 0.08), ("Assignment", 0.3), ("Due", 0.78), ("Grade", 0.9)]
    p.rect(LEFT, top - 22, RIGHT - LEFT, 22, fill=_s().tab)
    for name, at in cols:
        label(p, LEFT + (RIGHT - LEFT) * at + 6, top - 15, name, 9)
    for r in range(22):
        y = top - 22 - (r + 1) * 28
        p.rect(LEFT + 10, y + 8, 11, 11, stroke=_s().soft, width=1)
        p.line(LEFT, y, RIGHT, y)
    return p, "Assignment tracker"


def meeting_notes():
    p = Page()
    header(p, LEFT, TOP, "Meeting", 30)
    for i, name in enumerate(["Topic", "Date", "People"]):
        y = TOP - 40 - i * 28
        p.text(LEFT, y, name, 11, rgb=_s().soft, bold=True)
        p.line(LEFT + 64, y - 4, RIGHT, y - 4)
    label(p, LEFT, TOP - 142, "Notes", 12)
    lines(p, LEFT, RIGHT, TOP - 164, 13)
    label(p, LEFT, 196, "Actions", 12)
    checkbox_rows(p, LEFT, RIGHT, 172, 5)
    return p, "Meeting notes"


def journal():
    p = Page()
    header(p, LEFT, TOP, "Dear diary", 30)
    date_line(p)
    p.rect(LEFT, TOP - 250, RIGHT - LEFT, 210, stroke=_s().rule, width=1)
    p.text(LEFT + 10, TOP - 60, "A sketch, a photo or a sticker", 9, rgb=_s().soft)
    lines(p, LEFT, RIGHT, TOP - 280, 16)
    return p, "Journal"


LAYOUTS = [
    daily, time_blocks, weekly, monthly, goals, weekly_review,
    todo, priority_matrix, kanban, brain_dump,
    habit_tracker, mood_tracker, water_sleep, reading_log, budget, meal_plan, workout_log, gratitude,
    cornell, class_schedule, assignments, meeting_notes, journal,
]


def pack():
    """Every layout as one page each, with template.json."""
    pages, entries = [], []
    for i, make in enumerate(LAYOUTS):
        page, title = make()
        pages.append(page)
        entries.append({"pdfPage": i + 1, "title": title})
    return pages, {"mode": "pages", "pages": entries}


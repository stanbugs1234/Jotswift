"""Life spreads: goals and productivity, health and fitness, home and
family, study, self-care and work. Undated, two pages each."""

from spreads.kit import *  # noqa: F401,F403
from spreads.plan import _fill_in

DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


def _panels(p, x0, x1, top, bottom, names, kind="ruled", gap=15):
    """[names] stacked as panels filling [top]-[bottom]; each filled with
    lines or checkboxes."""
    h = (top - bottom) / len(names)
    for i, name in enumerate(names):
        t = panel(p, x0, top - i * h, x1 - x0, h - 6, name)
        (checks if kind == "checks" else ruled)(p, x0 + 5, x1 - 5, t, top - (i + 1) * h + 4, gap)


def _grid_panels(p, x0, x1, top, bottom, names, cols=2, kind="ruled"):
    rows = (len(names) + cols - 1) // cols
    h = (top - bottom) / rows
    for i, name in enumerate(names):
        c0, c1 = split(x0, x1, *([1] * cols), gap=8)[i % cols]
        r = i // cols
        t = panel(p, c0, top - r * h, c1 - c0, h - 8, name)
        (checks if kind == "checks" else ruled)(p, c0 + 5, c1 - 5, t, top - (r + 1) * h + 6, 15)


# Goals & productivity


def swot(sp):
    """Strengths, weaknesses, opportunities and threats around a centre,
    with an action plan."""
    p = sp.page
    x0, x1 = sp.left
    _fill_in(p, x0 + 160, TOP + 10, "For")
    names = [("Strengths", "Weaknesses"), ("Opportunities", "Threats")]
    h = (TOP - 4 - BOTTOM) / 2
    for r, pair in enumerate(names):
        for (c0, c1), name in zip(split(x0, x1, 1, 1, gap=6), pair):
            t = panel(p, c0, TOP - 4 - r * h, c1 - c0, h - 6, name)
            ruled(p, c0 + 5, c1 - 5, t, TOP - (r + 1) * h + 4, 15)
    # Just below the lower headings, so it doesn't cover them.
    cx, cy = (x0 + x1) / 2, (TOP + BOTTOM) / 2 - 2 - 15 - 40
    circle(p, cx, cy, 34, sp.colourway.paper)
    circle(p, cx, cy, 34, S().accent, fill=False, width=1.4)
    p.text(cx, cy - 4, "SWOT", 11, rgb=S().accent, bold=True, center=True)
    rx0, rx1 = sp.right
    ledger(p, rx0, rx1, TOP - 4, 300, "Action plan", [("Do", 0), ("Action", 0.08), ("By", 0.78)], check=True)
    t = panel(p, rx0, TOP - 310, rx1 - rx0, TOP - 310 - BOTTOM, "Key takeaways")
    ruled(p, rx0 + 5, rx1 - 5, t, BOTTOM + 2, 15)


def smart(sp):
    """A SMART goal, with steps, milestones and a reward."""
    p = sp.page
    x0, x1 = sp.left
    t = panel(p, x0, TOP - 4, x1 - x0, 60, "My goal")
    ruled(p, x0 + 5, x1 - 5, t, TOP - 60, 16)
    _panels(p, x0, x1, TOP - 70, BOTTOM, ["Specific", "Measurable", "Achievable", "Relevant", "Time-bound"])
    rx0, rx1 = sp.right
    t = panel(p, rx0, TOP - 4, rx1 - rx0, 230, "Steps")
    checks(p, rx0 + 5, rx1 - 5, t, TOP - 234, 15)
    ledger(p, rx0, rx1, TOP - 240, 170, "Milestones", [("Milestone", 0), ("By", 0.6), ("Done", 0.82)])
    _panels(p, rx0, rx1, TOP - 416, BOTTOM, ["My reward", "Why it matters"])


def plan_90(sp):
    """Ninety days: three months of goals and twelve weeks to tick off."""
    p = sp.page
    x0, x1 = sp.left
    _fill_in(p, x0 + 160, TOP + 10, "Starting")
    for (c0, c1), name in zip(split(x0, x1, 1, 1, 1, gap=6), ("Month 1", "Month 2", "Month 3")):
        t = panel(p, c0, TOP - 4, c1 - c0, TOP - 4 - BOTTOM, name)
        caps(p, c0 + 5, t - 12, "Focus", 6, rgb=S().soft)
        ruled(p, c0 + 5, c1 - 5, t - 14, t - 60, 15)
        caps(p, c0 + 5, t - 74, "Goals", 6, rgb=S().soft)
        checks(p, c0 + 5, c1 - 5, t - 76, BOTTOM + 2, 15)
    rx0, rx1 = sp.right
    _grid_panels(p, rx0, rx1, TOP - 4, BOTTOM, [f"Week {i}" for i in range(1, 13)], cols=3, kind="checks")


def project(sp):
    """A project: overview, milestones, tasks and notes."""
    p = sp.page
    x0, x1 = sp.left
    t = panel(p, x0, TOP - 4, x1 - x0, 120, "Project")
    for i, name in enumerate(("Name", "Goal", "Start", "Due", "People")):
        y = t - 18 - i * 20
        caps(p, x0 + 6, y, name, 6.5, rgb=S().soft)
        p.line(x0 + 60, y - 1, x1 - 8, y - 1, rgb=S().rule, width=0.5)
    ledger(p, x0, x1, TOP - 130, TOP - 130 - BOTTOM, "Milestones",
           [("Done", 0), ("Milestone", 0.09), ("Owner", 0.6), ("Due", 0.8)], check=True)
    rx0, rx1 = sp.right
    t = panel(p, rx0, TOP - 4, rx1 - rx0, 330, "Tasks")
    (a0, a1), (b0, b1) = split(rx0 + 5, rx1 - 5, 1, 1, gap=10)
    checks(p, a0, a1, t, TOP - 334, 15)
    checks(p, b0, b1, t, TOP - 334, 15)
    t = panel(p, rx0, TOP - 340, rx1 - rx0, TOP - 340 - BOTTOM, "Notes")
    ruled(p, rx0 + 5, rx1 - 5, t, BOTTOM + 2, 15)


def matrix(sp):
    """Do, plan, hand off, drop: the priority matrix, with notes."""
    p = sp.page
    x0, x1 = sp.left
    _grid_panels(p, x0, x1, TOP - 4, BOTTOM, ["Urgent & important: do", "Important: plan",
                                                "Urgent: hand off", "Neither: drop"], cols=2, kind="checks")
    rx0, rx1 = sp.right
    ledger(p, rx0, rx1, TOP - 4, 280, "Handed off", [("Task", 0), ("To", 0.6), ("Check by", 0.8)])
    t = panel(p, rx0, TOP - 290, rx1 - rx0, TOP - 290 - BOTTOM, "Notes")
    ruled(p, rx0 + 5, rx1 - 5, t, BOTTOM + 2, 15)


def mind_map(sp):
    """A centre idea with branches on the left; notes on the right."""
    p = sp.page
    x0, x1 = sp.left
    cx, cy = (x0 + x1) / 2, (TOP + BOTTOM) / 2
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        bx, by = cx + 130 * math.cos(a), cy + 200 * math.sin(a)
        p.line(cx + 46 * math.cos(a), cy + 46 * math.sin(a), bx, by, rgb=tint_accent(), width=1.2)
        p.rect(bx - 40, by - 13, 80, 26, stroke=S().rule, width=0.8)
    circle(p, cx, cy, 46, S().tab)
    circle(p, cx, cy, 46, S().accent, fill=False, width=1.4)
    rx0, rx1 = sp.right
    t = panel(p, rx0, TOP - 4, rx1 - rx0, TOP - 4 - BOTTOM, "Notes")
    ruled(p, rx0 + 5, rx1 - 5, t, BOTTOM + 2, 15)


def tint_accent():
    return tuple(c + (1 - c) * 0.45 for c in S().accent)


def review(sp, n=1):
    """A weekly review: wins, challenges, lessons and next week's focus."""
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Week of")
    _panels(p, *sp.left, TOP - 4, BOTTOM, ["Wins", "Challenges", "What I learned"])
    rx0, rx1 = sp.right
    t = panel(p, rx0, TOP - 4, rx1 - rx0, 90, "Rate the week")
    for i, area in enumerate(("Work", "Health", "People", "Rest", "Money")):
        x = rx0 + 8 + i * ((rx1 - rx0 - 16) / 5)
        caps(p, x, t - 14, area, 6, rgb=S().soft)
        for s in range(5):
            circle(p, x + 6 + s * 11, t - 30, 4, S().rule, fill=False, width=0.7)
    _panels(p, rx0, rx1, TOP - 100, BOTTOM, ["Next week's focus", "To carry over"], kind="checks")


# Health & fitness


def workout(sp, n=1):
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Date")
    ledger(p, *sp.left, TOP - 4, TOP - 4 - BOTTOM, "Strength",
           [("Exercise", 0), ("Sets", 0.42), ("Reps", 0.56), ("Weight", 0.7), ("Done", 0.86)], row_h=17)
    rx0, rx1 = sp.right
    ledger(p, rx0, rx1, TOP - 4, 220, "Cardio", [("Activity", 0), ("Time", 0.45), ("Distance", 0.64), ("Felt", 0.84)])
    _panels(p, rx0, rx1, TOP - 230, BOTTOM, ["Stretch & recover", "Notes"])


def meals(sp, n=1):
    """A week of meals and the grocery list for it."""
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Week of")
    x0, x1 = sp.left
    t = panel(p, x0, TOP - 4, x1 - x0, TOP - 4 - BOTTOM, "Meal plan")
    table(p, t - 2, [("", 0), ("Breakfast", 0.12), ("Lunch", 0.34), ("Dinner", 0.56), ("Snacks", 0.78)], 7,
          row_h=(t - 26 - BOTTOM) / 7, x0=x0 + 4, x1=x1 - 4)
    rh = (t - 26 - BOTTOM) / 7
    for i, d in enumerate(DAYS):
        caps(p, x0 + 8, t - 2 - 22 - (i + 1) * rh + rh / 2 - 2, d, 7)
    _grid_panels(p, *sp.right, TOP - 4, BOTTOM,
                 ["Fruit & veg", "Meat & fish", "Dairy", "Bakery", "Pantry", "Other"], cols=2, kind="checks")


def food(sp, n=1):
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Date")
    _panels(p, *sp.left, TOP - 4, BOTTOM, ["Breakfast", "Lunch", "Dinner", "Snacks"])
    rx0, rx1 = sp.right
    t = panel(p, rx0, TOP - 4, rx1 - rx0, 70, "Water")
    gw = (rx1 - rx0 - 12) / 10
    for i in range(10):
        p.rect(rx0 + 6 + i * gw + 2, t - 40, gw - 4, 30, stroke=S().rule, width=0.6)
    _panels(p, rx0, rx1, TOP - 80, BOTTOM, ["How I felt", "Notes"])


def body(sp):
    """Weight and measurements, and a chart."""
    p = sp.page
    ledger(p, *sp.left, TOP - 4, TOP - 4 - BOTTOM, "Measurements",
           [("Date", 0), ("Weight", 0.18), ("Waist", 0.36), ("Hips", 0.52), ("Chest", 0.68), ("Notes", 0.84)],
           row_h=17)
    rx0, rx1 = sp.right
    t = panel(p, rx0, TOP - 4, rx1 - rx0, 330, "Progress")
    left, base = rx0 + 26, t - 300
    p.line(left, base, rx1 - 10, base, rgb=S().soft, width=0.8)
    p.line(left, base, left, t - 10, rgb=S().soft, width=0.8)
    dots(p, left + 8, base + 8, rx1 - 16, t - 16, 14)
    t = panel(p, rx0, TOP - 340, rx1 - rx0, TOP - 340 - BOTTOM, "Goals")
    checks(p, rx0 + 5, rx1 - 5, t, BOTTOM + 2, 15)


def medication(sp, n=1):
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Month")
    ledger(p, *sp.left, TOP - 4, TOP - 4 - BOTTOM, "Medicines & vitamins",
           [("Name", 0), ("Dose", 0.4), ("When", 0.6), ("For", 0.8)], row_h=18)
    rx0, rx1 = sp.right
    t = panel(p, rx0, TOP - 4, rx1 - rx0, TOP - 4 - BOTTOM, "Taken")
    name_w = 40
    cw = (rx1 - rx0 - name_w - 8) / 8
    rh = (t - BOTTOM - 8) / 31
    for d in range(31):
        y = t - 4 - (d + 1) * rh
        p.text(rx0 + 8, y + rh / 2 - 2, str(d + 1), 5.5, rgb=S().soft, bold=True)
        for m in range(8):
            p.rect(rx0 + name_w + m * cw + 2, y + 1, cw - 4, rh - 2, stroke=S().rule, width=0.4)


# Home & family


def cleaning(sp):
    p = sp.page
    _panels(p, *sp.left, TOP - 4, BOTTOM, ["Every day", "Every week"], kind="checks")
    _panels(p, *sp.right, TOP - 4, BOTTOM, ["Every month", "Every season"], kind="checks")


def chores(sp, n=1):
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Week of")
    for (x0, x1), title in ((sp.left, "Chores"), (sp.right, "More chores")):
        t = panel(p, x0, TOP - 4, x1 - x0, TOP - 4 - BOTTOM, title)
        table(p, t - 2, [("Chore / who", 0)] + [(d, 0.38 + i * 0.088) for i, d in enumerate(DAYS)], 16,
              row_h=(t - 26 - BOTTOM) / 16, x0=x0 + 4, x1=x1 - 4)


def recipe(sp):
    p = sp.page
    x0, x1 = sp.left
    t = panel(p, x0, TOP - 4, x1 - x0, 80, "Recipe")
    for i, name in enumerate(("Name", "Serves  ____   Prep  ____   Cook  ____")):
        caps(p, x0 + 6, t - 18 - i * 22, name, 6.5, rgb=S().soft)
    p.line(x0 + 40, t - 19, x1 - 8, t - 19, rgb=S().rule, width=0.5)
    t = panel(p, x0, TOP - 90, x1 - x0, TOP - 90 - BOTTOM, "Ingredients")
    checks(p, x0 + 5, x1 - 5, t, BOTTOM + 2, 16)
    rx0, rx1 = sp.right
    t = panel(p, rx0, TOP - 4, rx1 - rx0, 380, "Method")
    y = t - 16
    k = 1
    while y > TOP - 380:
        p.text(rx0 + 7, y + 2, f"{k}.", 7, rgb=S().accent, bold=True)
        p.line(rx0 + 20, y, rx1 - 6, y, rgb=S().rule, width=0.5)
        y -= 18
        k += 1
    t = panel(p, rx0, TOP - 390, rx1 - rx0, TOP - 390 - BOTTOM, "Notes")
    ruled(p, rx0 + 5, rx1 - 5, t, BOTTOM + 2, 15)


def contacts(sp):
    cols = [("Name", 0), ("Phone", 0.32), ("Email", 0.55), ("Birthday", 0.84)]
    for (x0, x1) in (sp.left, sp.right):
        ledger(sp.page, x0, x1, TOP - 4, TOP - 4 - BOTTOM, "Contacts", cols, row_h=18)


def home_care(sp):
    p = sp.page
    ledger(p, *sp.left, TOP - 4, TOP - 4 - BOTTOM, "Home maintenance",
           [("Task", 0), ("How often", 0.42), ("Last done", 0.62), ("Next", 0.82)], row_h=17)
    _panels(p, *sp.right, TOP - 4, BOTTOM, ["Repairs to make", "Useful numbers"], kind="checks")


# Study


def timetable(sp):
    p = sp.page
    x0, x1 = sp.left
    t = panel(p, x0, TOP - 4, x1 - x0, TOP - 4 - BOTTOM, "Timetable")
    table(p, t - 2, [("", 0)] + [(d, 0.1 + i * 0.18) for i, d in enumerate(DAYS[:5])], 9,
          row_h=(t - 26 - BOTTOM) / 9, x0=x0 + 4, x1=x1 - 4)
    rh = (t - 26 - BOTTOM) / 9
    for i in range(9):
        caps(p, x0 + 9, t - 2 - 22 - (i + 1) * rh + rh / 2 - 2, str(i + 1), 8)
    ledger(p, *sp.right, TOP - 4, TOP - 4 - BOTTOM, "Classes",
           [("Class", 0), ("Teacher", 0.34), ("Room", 0.62), ("Contact", 0.76)], row_h=18)


def assignments(sp):
    cols = [("Done", 0), ("Class", 0.09), ("Assignment", 0.3), ("Due", 0.74), ("Grade", 0.87)]
    for x0, x1 in (sp.left, sp.right):
        ledger(sp.page, x0, x1, TOP - 4, TOP - 4 - BOTTOM, "Assignments", cols, row_h=17, check=True)


def exams(sp):
    p = sp.page
    ledger(p, *sp.left, TOP - 4, TOP - 4 - BOTTOM, "Exams",
           [("Subject", 0), ("Date", 0.36), ("Time", 0.52), ("Room", 0.66), ("Topics", 0.8)], row_h=18)
    rx0, rx1 = sp.right
    for (c0, c1), name in zip(split(rx0, rx1, 1, 1, 1, gap=6), ("2 weeks before", "1 week before", "The day before")):
        t = panel(p, c0, TOP - 4, c1 - c0, TOP - 4 - BOTTOM, name)
        checks(p, c0 + 5, c1 - 5, t, BOTTOM + 2, 15)


def study(sp, n=1):
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Week of")
    day_columns(p, *sp.left, TOP - 4, BOTTOM, DAYS[:4], gap=15)
    rx0, rx1 = sp.right
    day_columns(p, rx0, rx1, TOP - 4, BOTTOM + 130, DAYS[4:], gap=15)
    t = panel(p, rx0, BOTTOM + 124, rx1 - rx0, 124, "Focus sessions (a box each)")
    cw = (rx1 - rx0 - 12) / 20
    for r in range(4):
        for i in range(20):
            p.rect(rx0 + 6 + i * cw + 1.5, t - 16 - r * 24, cw - 3, 16, stroke=S().rule, width=0.5)


def grades(sp):
    p = sp.page
    ledger(p, *sp.left, TOP - 4, TOP - 4 - BOTTOM, "Grades",
           [("Course", 0), ("Credits", 0.46), ("Grade", 0.64), ("Points", 0.82)], row_h=18)
    rx0, rx1 = sp.right
    for (c0, c1), name in zip(split(rx0, rx1, 1, 1, 1, gap=6), ("Credits", "Points", "GPA")):
        panel(p, c0, TOP - 4, c1 - c0, 70, name)
    ledger(p, rx0, rx1, TOP - 80, TOP - 80 - BOTTOM, "Tests & scores",
           [("Test", 0), ("Course", 0.4), ("Score", 0.66), ("Weight", 0.84)])


# Self-care & journal


def gratitude(sp, n=1):
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Week of")
    _panels(p, *sp.left, TOP - 4, BOTTOM, DAYS[:4], gap=14)
    _panels(p, *sp.right, TOP - 4, BOTTOM, DAYS[4:] + ["This week I'm proud of"], gap=14)


def reflection(sp, n=1):
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Date")
    _panels(p, *sp.left, TOP - 4, BOTTOM, ["How I feel today", "What's on my mind", "What went well"])
    _panels(p, *sp.right, TOP - 4, BOTTOM, ["What I'd do differently", "Tomorrow I will", "A kind word to myself"])


def self_care(sp):
    p = sp.page
    _grid_panels(p, *sp.left, TOP - 4, BOTTOM, ["Body", "Mind", "Heart", "Rest", "Fun", "Space"], cols=2,
                 kind="checks")
    rx0, rx1 = sp.right
    habit_grid(p, rx0, TOP - 4, rx1 - rx0, 300, "This week", 10)
    t = panel(p, rx0, TOP - 310, rx1 - rx0, TOP - 310 - BOTTOM, "Notes to self")
    ruled(p, rx0 + 5, rx1 - 5, t, BOTTOM + 2, 15)


def affirmations(sp):
    p = sp.page
    x0, x1 = sp.left
    h = (TOP - 4 - BOTTOM) / 5
    for i in range(5):
        y = TOP - 4 - (i + 1) * h + 6
        p.rect(x0, y, x1 - x0, h - 10, fill=S().tab)
        p.line(x0 + 20, y + (h - 10) / 2, x1 - 20, y + (h - 10) / 2, rgb=S().rule, width=0.6)
    rx0, rx1 = sp.right
    t = panel(p, rx0, TOP - 4, rx1 - rx0, TOP - 4 - BOTTOM, "I am")
    ruled(p, rx0 + 5, rx1 - 5, t, BOTTOM + 2, 20)


def reading(sp):
    p = sp.page
    ledger(p, *sp.left, TOP - 4, TOP - 4 - BOTTOM, "Books read",
           [("Title", 0), ("Author", 0.42), ("Finished", 0.66), ("Rating", 0.84)], row_h=18)
    _panels(p, *sp.right, TOP - 4, BOTTOM, ["To read", "Favourite quotes"], kind="checks")


def bucket(sp):
    p = sp.page
    k = 1
    for x0, x1 in (sp.left, sp.right):
        t = panel(p, x0, TOP - 4, x1 - x0, TOP - 4 - BOTTOM, "Bucket list")
        y = t - 16
        while y > BOTTOM + 4:
            p.text(x0 + 6, y + 1, f"{k}", 6.5, rgb=S().accent, bold=True)
            p.rect(x0 + 20, y, 7, 7, stroke=S().soft, width=0.7)
            p.line(x0 + 32, y, x1 - 6, y, rgb=S().rule, width=0.5)
            y -= 17
            k += 1


# Work & business


def clients(sp):
    cols = [("Client", 0), ("Contact", 0.3), ("Project", 0.56), ("Status", 0.82)]
    for x0, x1 in (sp.left, sp.right):
        ledger(sp.page, x0, x1, TOP - 4, TOP - 4 - BOTTOM, "Clients", cols, row_h=18)


def income(sp, n=1):
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Month")
    ledger(p, *sp.left, TOP - 4, TOP - 4 - BOTTOM, "Income",
           [("Date", 0), ("From", 0.16), ("For", 0.46), ("Amount", 0.8)], row_h=17)
    rx0, rx1 = sp.right
    ledger(p, rx0, rx1, TOP - 4, 330, "Business expenses",
           [("Date", 0), ("What", 0.16), ("Category", 0.56), ("Amount", 0.8)])
    for (c0, c1), name in zip(split(rx0, rx1, 1, 1, 1, gap=6), ("Income", "Expenses", "Profit")):
        panel(p, c0, TOP - 340, c1 - c0, TOP - 340 - BOTTOM, name)


def content(sp, n=1):
    p = sp.page
    _fill_in(p, sp.left[0] + 160, TOP + 10, "Month")
    cols = [("Date", 0), ("Platform", 0.14), ("Idea / topic", 0.36), ("Status", 0.78)]
    for x0, x1 in (sp.left, sp.right):
        ledger(p, x0, x1, TOP - 4, TOP - 4 - BOTTOM, "Content calendar", cols, row_h=18)


def meeting(sp, n=1):
    p = sp.page
    x0, x1 = sp.left
    t = panel(p, x0, TOP - 4, x1 - x0, 100, "Meeting")
    for i, name in enumerate(("Topic", "Date", "Time", "People")):
        y = t - 16 - i * 20
        caps(p, x0 + 6, y, name, 6.5, rgb=S().soft)
        p.line(x0 + 54, y - 1, x1 - 8, y - 1, rgb=S().rule, width=0.5)
    t = panel(p, x0, TOP - 110, x1 - x0, TOP - 110 - BOTTOM, "Agenda")
    checks(p, x0 + 5, x1 - 5, t, BOTTOM + 2, 16)
    rx0, rx1 = sp.right
    t = panel(p, rx0, TOP - 4, rx1 - rx0, 320, "Notes")
    ruled(p, rx0 + 5, rx1 - 5, t, TOP - 324, 15)
    ledger(p, rx0, rx1, TOP - 330, TOP - 330 - BOTTOM, "Actions",
           [("Done", 0), ("Action", 0.1), ("Who", 0.66), ("By", 0.84)], check=True)


def invoices(sp):
    cols = [("Paid", 0), ("Invoice", 0.09), ("Client", 0.26), ("Sent", 0.56), ("Due", 0.7), ("Amount", 0.84)]
    for x0, x1 in (sp.left, sp.right):
        ledger(sp.page, x0, x1, TOP - 4, TOP - 4 - BOTTOM, "Invoices", cols, row_h=17, check=True)


TITLES = {
    swot: "SWOT analysis", smart: "SMART goal", plan_90: "90-day plan", project: "Project planner",
    matrix: "Priority matrix", mind_map: "Mind map", review: "Weekly review",
    workout: "Workout log", meals: "Meal planner", food: "Food diary", body: "Body & weight",
    medication: "Medication",
    cleaning: "Cleaning schedule", chores: "Chore chart", recipe: "Recipe", contacts: "Contacts & birthdays",
    home_care: "Home maintenance",
    timetable: "Class timetable", assignments: "Assignments", exams: "Exam planner", study: "Study planner",
    grades: "Grades",
    gratitude: "Gratitude", reflection: "Daily reflection", self_care: "Self-care", affirmations: "Affirmations",
    reading: "Reading log", bucket: "Bucket list",
    clients: "Clients", income: "Income & expenses", content: "Content calendar", meeting: "Meeting notes",
    invoices: "Invoices",
}

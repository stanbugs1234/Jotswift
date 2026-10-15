"""Wellness pages: year-long habit and mood grids, steps, sleep, cycles,
medication, symptoms and self-care."""

from layouts.kit import *  # noqa: F401,F403

MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def _key(p, y, names):
    x = LEFT
    for i, name in enumerate(names):
        p.rect(x, y - 2, 12, 12, fill=tint(s().accent, 0.15 + i * 0.18), stroke=s().rule, width=0.5)
        p.text(x + 18, y, name, 8.5, rgb=s().soft)
        x += 30 + mp_width(name)


def mp_width(name):
    import make_planner as mp
    return mp.text_width(name, 8.5)


def habit_year():
    p = page("A year of one habit", "Habit  ________________   Year  ______", size=26)
    day_grid(p, TOP - 50, MONTHS, name_w=34, row_h=40)
    label(p, LEFT, 160, "Why this habit")
    lines(p, LEFT, RIGHT, 136, 3)
    return p, "Habit tracker (year)"


def mood_year():
    p = page("Year in moods", "Year  ______  Colour each day", size=26)
    bottom = day_grid(p, TOP - 50, MONTHS, name_w=34, row_h=40)
    _key(p, bottom - 30, ["Great", "Good", "Okay", "Low", "Hard"])
    label(p, LEFT, bottom - 70, "Patterns I notice")
    lines(p, LEFT, RIGHT, bottom - 94, 3)
    return p, "Mood tracker (year)"


def steps():
    p = page("Steps & movement", "Month  ________________", size=26)
    table(p, TOP - 40, [("Day", 0), ("Steps", 0.1), ("Activity", 0.32), ("Minutes", 0.72), ("Felt", 0.86)], 31, row_h=19)
    return p, "Steps tracker"


def sleep_log():
    p = page("Sleep", "Week of  ________________")
    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    hours = ["8p", "10p", "12a", "2a", "4a", "6a", "8a", "10a"]
    top, x0 = TOP - 60, LEFT + 40
    cw = (RIGHT - x0) / 14
    for i, h in enumerate(hours):
        p.text(x0 + i * 2 * cw, top + 6, h, 8, rgb=s().soft, center=True)
    for r, d in enumerate(days):
        y = top - (r + 1) * 34
        p.text(LEFT, y + 12, d, 10, rgb=s().accent, bold=True)
        for c in range(14):
            p.rect(x0 + c * cw, y + 4, cw, 24, stroke=s().rule, width=0.6)
    y = top - 7 * 34 - 40
    bottom = table(p, y, [("Day", 0), ("Hours", 0.14), ("Quality", 0.3), ("Notes", 0.5)], 7, row_h=26)
    label(p, LEFT, bottom - 26, "What helps me sleep")
    lines(p, LEFT, RIGHT, bottom - 50, 3)
    return p, "Sleep log"


def cycle_tracker():
    p = page("Cycle", "Year  ______", size=26)
    bottom = day_grid(p, TOP - 50, MONTHS, name_w=34, row_h=36)
    _key(p, bottom - 28, ["Period", "Spotting", "Symptoms", "Mood", "Energy"])
    label(p, LEFT, bottom - 64, "Notes")
    lines(p, LEFT, RIGHT, bottom - 88, int((bottom - 88 - BOTTOM) / 26) + 1)
    return p, "Cycle tracker"


def medication():
    p = page("Medication", "Month  ________________")
    bottom = table(p, TOP - 40, [("Medicine", 0), ("Dose", 0.34), ("When", 0.52), ("For", 0.72)], 6, row_h=28)
    label(p, LEFT, bottom - 24, "Taken")
    day_grid(p, bottom - 44, ["", "", "", "", "", ""], name_w=80, row_h=30, bottom=BOTTOM)
    return p, "Medication tracker"


def symptoms():
    p = page("Symptoms", "Month  ________________")
    table(p, TOP - 40, [("Date", 0), ("Symptom", 0.13), ("Level 1-10", 0.38), ("Possible trigger", 0.54), ("Helped", 0.8)],
          20, row_h=30)
    return p, "Symptom log"


def self_care():
    p = page("Self-care", "Week of  ________________")
    ideas = [("Body", ["Walk outside", "Stretch", "Drink water", "Early night"]),
             ("Mind", ["Read", "Journal", "No-phone hour", "Learn something"]),
             ("Heart", ["Call a friend", "Kind note", "Laugh", "Hug"]),
             ("Rest", ["Nap", "Bath", "Music", "Do nothing"])]
    xs, w = columns(p, LEFT, RIGHT, 2, gap=16)
    for i, (name, items) in enumerate(ideas):
        x = xs[i % 2]
        y = TOP - 44 - (i // 2 + 1) * 160 - (i // 2) * 12
        p.rect(x, y, w, 160, fill=tint(s().accent, 0.93))
        label(p, x + 10, y + 140, name, 11)
        for k, item in enumerate(items):
            iy = y + 114 - k * 26
            p.rect(x + 10, iy - 2, 11, 11, stroke=s().soft, width=1)
            p.text(x + 28, iy, item, 9.5)
    y = TOP - 44 - 2 * 172
    label(p, LEFT, y - 20, "How I'm feeling")
    lines(p, LEFT, RIGHT, y - 44, 4)
    label(p, LEFT, y - 170, "One kind thing for myself this week")
    lines(p, LEFT, RIGHT, y - 194, 2)
    return p, "Self-care"


LAYOUTS = [habit_year, mood_year, steps, sleep_log, cycle_tracker, medication, symptoms, self_care]

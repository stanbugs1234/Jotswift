"""Journal pages. Layouts that take [n] are repeated, once per day; [n]
starts at 1. Prompts rotate so days don't all ask the same thing."""

import datetime as dt

from layouts.kit import *  # noqa: F401,F403

MORNING = [
    "Today I want to feel", "One thing I'm looking forward to", "My intention for today",
    "What would make today great?", "Something I can let go of", "Who can I help today?",
    "A small win I'm aiming for",
]
EVENING = [
    "The best part of today", "Something I learned", "A moment I want to remember",
    "What I'd do differently", "Someone who made my day better", "What drained me, what filled me",
    "Tomorrow I'll try",
]
REFLECT = [
    "What am I proud of lately?", "What is taking up space in my head?", "What do I need more of?",
    "What did I avoid this week, and why?", "What would my future self thank me for?",
    "When did I feel most like myself?", "What am I ready to change?", "What surprised me?",
    "What boundaries do I need?", "What does a good day look like for me?",
]
GRATITUDE = [
    "A person I'm grateful for", "A place I love", "Something that made me smile",
    "A skill I'm glad I have", "A comfort I take for granted", "Something beautiful I saw",
    "A memory I treasure", "Something about my body I appreciate", "A lesson that helped me",
    "A small luxury",
]


def _day_head(p, title, n, sub="Date  ________________"):
    header(p, LEFT, TOP, title, 26)
    p.text(RIGHT, TOP + 2, f"Day {n}", 11, rgb=s().soft, bold=True, right=True)
    p.text(LEFT, TOP - 22, sub, 11, rgb=s().soft)


def _prompt(p, y, text, count, gap=26):
    label(p, LEFT, y, text, 11)
    lines(p, LEFT, RIGHT, y - 24, count, gap)
    return y - 24 - count * gap - 18


def title_page(name, intro):
    """A first page: the journal's name, who it belongs to, how to use it."""
    def make():
        p = page(name, False, size=34)
        field(p, LEFT, TOP - 60, "This journal belongs to", RIGHT, size=11)
        field(p, LEFT, TOP - 92, "Started on", LEFT + 250, size=11)
        label(p, LEFT, TOP - 150, "How to use it", 12)
        y = TOP - 176
        for line in intro:
            p.text(LEFT, y, line, 10.5)
            y -= 20
        return p, "Start here"
    return make


def morning(n):
    p = Page()
    _day_head(p, "Sunrise", n)
    p.rect(LEFT, TOP - 74, RIGHT - LEFT, 34, fill=tint(s().accent, 0.92))
    p.text(LEFT + 10, TOP - 61, "I slept     1   2   3   4   5          Energy     1   2   3   4   5", 10, rgb=s().soft)
    y = _prompt(p, TOP - 104, "I'm grateful for", 3)
    y = _prompt(p, y, MORNING[(n - 1) % len(MORNING)], 3)
    label(p, LEFT, y, "Top 3 for today", 11)
    numbered(p, LEFT, RIGHT, y - 24, 3)
    y -= 24 + 3 * 26 + 18
    y = _prompt(p, y, "Affirmation", 2)
    _prompt(p, y, "Notes", max(1, int((y - 24 - BOTTOM) / 26)))
    return p, f"Day {n} morning"


def evening(n):
    p = Page()
    _day_head(p, "Sunset", n)
    y = _prompt(p, TOP - 56, EVENING[(n - 1) % len(EVENING)], 4)
    y = _prompt(p, y, "Three good things", 3)
    label(p, LEFT, y, "Today felt", 11)
    for i, word in enumerate(("Great", "Good", "Okay", "Low", "Hard")):
        x = LEFT + 90 + i * 84
        p.rect(x, y - 4, 12, 12, stroke=s().soft, width=1)
        p.text(x + 18, y - 2, word, 10)
    y -= 40
    _prompt(p, y, "Let it out", max(1, int((y - 24 - BOTTOM) / 26)))
    return p, f"Day {n} evening"


def gratitude_day(n):
    p = Page()
    _day_head(p, "Gratitude", n)
    y = TOP - 56
    for i in range(3):
        p.text(LEFT, y - 2, f"{i + 1}", 18, rgb=tint(s().accent, 0.3), bold=True)
        lines(p, LEFT + 24, RIGHT, y, 2)
        y -= 70
    y = _prompt(p, y, GRATITUDE[(n - 1) % len(GRATITUDE)], 4)
    p.rect(LEFT, BOTTOM, RIGHT - LEFT, y - BOTTOM - 10, stroke=s().rule)
    p.text(LEFT + 10, y - 26, "A sketch, photo or sticker", 9, rgb=s().soft)
    return p, f"Day {n}"


def five_year_day(n):
    """One date of the year, with a box for each of five years. [n] is the
    day of a leap year, so February 29 has a page."""
    day = dt.date(2028, 1, 1) + dt.timedelta(days=n - 1)
    p = Page()
    header(p, LEFT, TOP, day.strftime("%B ") + str(day.day), 28)
    p.text(RIGHT, TOP + 2, "Five years, one page", 9, rgb=s().soft, right=True)
    bh = (TOP - 30 - BOTTOM - 4 * 10) / 5
    for i in range(5):
        y = TOP - 30 - (i + 1) * bh - i * 10
        p.rect(LEFT, y, RIGHT - LEFT, bh, stroke=s().rule)
        p.text(LEFT + 10, y + bh - 20, "20", 12, rgb=s().accent, bold=True)
        p.line(LEFT + 28, y + bh - 22, LEFT + 52, y + bh - 22, rgb=s().accent)
        lines(p, LEFT + 10, RIGHT - 10, y + bh - 44, int((bh - 40) / 24), gap=24)
    return p, day.strftime("%B ") + str(day.day)


def reflection(n):
    p = Page()
    _day_head(p, "Reflection", n)
    y = _prompt(p, TOP - 56, REFLECT[(n - 1) % len(REFLECT)], 12)
    _prompt(p, y, "What I'll carry forward", max(1, int((y - 24 - BOTTOM) / 26)))
    return p, f"Reflection {n}"


def dream():
    p = page("Dream journal")
    p.rect(LEFT, TOP - 72, RIGHT - LEFT, 30, fill=tint(s().accent, 0.92))
    p.text(LEFT + 10, TOP - 61, "Clear     1   2   3   4   5          Lucid?   yes   no          Recurring?   yes   no",
           9.5, rgb=s().soft)
    y = _prompt(p, TOP - 100, "What happened", 9)
    xs, w = columns(p, LEFT, RIGHT, 2)
    for x, name in zip(xs, ("People & places", "Feelings")):
        box(p, x, y - 120, w, 120, name)
    y -= 150
    _prompt(p, y, "What it might mean", max(1, int((y - 24 - BOTTOM) / 26)))
    return p, "Dream journal"


def prayer():
    p = page("Prayer & reflection")
    y = _prompt(p, TOP - 56, "Reading or verse", 3)
    y = _prompt(p, y, "What it says to me", 4)
    xs, w = columns(p, LEFT, RIGHT, 2)
    for x, name in zip(xs, ("Praying for", "Thankful for")):
        box(p, x, y - 170, w, 170, name)
        checkbox_rows(p, x + 10, x + w - 10, y - 44, 5, gap=24)
    y -= 196
    _prompt(p, y, "Answered", max(1, int((y - 24 - BOTTOM) / 26)))
    return p, "Prayer journal"


LAYOUTS = [morning, evening, gratitude_day, five_year_day, reflection, dream, prayer]
